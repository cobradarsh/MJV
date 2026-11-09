#import "FrameSource.h"
#import "Shared.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>

static void OCFillPixelBufferBlack(CVPixelBufferRef buffer) {
    const OSType format = CVPixelBufferGetPixelFormatType(buffer);
    const size_t planeCount = CVPixelBufferGetPlaneCount(buffer);

    if (CVPixelBufferIsPlanar(buffer) && planeCount > 0) {
        const BOOL fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                               format == kCVPixelFormatType_420YpCbCr8PlanarFullRange;
        for (size_t plane = 0; plane < planeCount; plane++) {
            uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane);
            if (base == NULL) {
                continue;
            }
            const size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane);
            const size_t height = CVPixelBufferGetHeightOfPlane(buffer, plane);
            const uint8_t value = plane == 0 ? (fullRange ? 0 : 16) : 128;
            for (size_t row = 0; row < height; row++) {
                memset(base + row * bytesPerRow, value, bytesPerRow);
            }
        }
        return;
    }

    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    if (base == NULL) {
        return;
    }

    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    const size_t height = CVPixelBufferGetHeight(buffer);
    uint8_t pixel[4] = {0, 0, 0, 255};
    if (format == kCVPixelFormatType_32ARGB || format == kCVPixelFormatType_32ABGR) {
        pixel[0] = 255;
        pixel[3] = 0;
    }

    const BOOL fourBytesPerPixel = format == kCVPixelFormatType_32BGRA ||
                                   format == kCVPixelFormatType_32RGBA ||
                                   format == kCVPixelFormatType_32ARGB ||
                                   format == kCVPixelFormatType_32ABGR;
    for (size_t row = 0; row < height; row++) {
        uint8_t *rowBase = base + row * bytesPerRow;
        if (fourBytesPerPixel) {
            const size_t width = CVPixelBufferGetWidth(buffer);
            for (size_t column = 0; column < width; column++) {
                memcpy(rowBase + column * 4, pixel, 4);
            }
        } else {
            memset(rowBase, 0, bytesPerRow);
        }
    }
}

@interface OCFrameSource () {
    dispatch_queue_t _decoderQueue;
    CIContext *_imageContext;
    CVPixelBufferRef _latestFrame;
    CGAffineTransform _frameTransform;
    NSUInteger _generation;
    uint64_t _sourceStamp;
    NSTimeInterval _lastConfigurationCheck;
    NSTimeInterval _retryAfter;
    BOOL _decoderRunning;
    BOOL _enabled;
    BOOL _blackScreen;
    int _notifyToken;
}
@end

@implementation OCFrameSource

+ (instancetype)sharedSource {
    static OCFrameSource *source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        source = [[self alloc] init];
    });
    return source;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _decoderQueue = dispatch_queue_create("com.opencam.virtualcamera.decoder", DISPATCH_QUEUE_SERIAL);
        _imageContext = [CIContext contextWithOptions:nil];
        _notifyToken = -1;

        __weak OCFrameSource *weakSelf = self;
        notify_register_dispatch(OCChangeNotification.UTF8String,
                                 &_notifyToken,
                                 dispatch_get_global_queue(QOS_CLASS_UTILITY, 0),
                                 ^(__unused int token) {
            [weakSelf configurationDidChange];
        });
    }
    return self;
}

- (void)dealloc {
    if (_notifyToken >= 0) {
        notify_cancel(_notifyToken);
    }
    if (_latestFrame != NULL) {
        CVPixelBufferRelease(_latestFrame);
    }
}

- (void)configurationDidChange {
    [self refreshConfigurationForced:YES];
}

- (BOOL)isGenerationActive:(NSUInteger)generation {
    @synchronized (self) {
        return _decoderRunning && generation == _generation && _enabled && !_blackScreen;
    }
}

- (void)stopDecoderLocked {
    _generation++;
    _decoderRunning = NO;
    if (_latestFrame != NULL) {
        CVPixelBufferRelease(_latestFrame);
        _latestFrame = NULL;
    }
}

- (void)startDecoderLockedWithStamp:(uint64_t)stamp {
    [self stopDecoderLocked];
    _sourceStamp = stamp;
    _decoderRunning = YES;
    _retryAfter = 0;
    const NSUInteger generation = _generation;
    NSString *path = [OCVideoPath() copy];
    dispatch_async(_decoderQueue, ^{
        [self decodeVideoAtPath:path generation:generation];
    });
}

- (void)decoderDidFailForGeneration:(NSUInteger)generation {
    @synchronized (self) {
        if (generation != _generation) {
            return;
        }
        _decoderRunning = NO;
        _retryAfter = CACurrentMediaTime() + 2.0;
        if (_latestFrame != NULL) {
            CVPixelBufferRelease(_latestFrame);
            _latestFrame = NULL;
        }
    }
}

- (void)refreshConfigurationForced:(BOOL)forced {
    const NSTimeInterval now = CACurrentMediaTime();
    @synchronized (self) {
        if (!forced && now - _lastConfigurationCheck < 0.25) {
            return;
        }
        _lastConfigurationCheck = now;
    }

    const BOOL enabled = access(OCEnabledPath().fileSystemRepresentation, F_OK) == 0;
    const BOOL blackScreen = access(OCBlackScreenPath().fileSystemRepresentation, F_OK) == 0;

    struct stat info;
    const BOOL hasVideo = stat(OCVideoPath().fileSystemRepresentation, &info) == 0 &&
                          S_ISREG(info.st_mode) && info.st_size > 0;
    uint64_t stamp = 0;
    if (hasVideo) {
        stamp = (uint64_t)info.st_ino ^
                ((uint64_t)info.st_size << 1) ^
                ((uint64_t)info.st_mtimespec.tv_sec << 17) ^
                ((uint64_t)info.st_mtimespec.tv_nsec << 33);
    }

    @synchronized (self) {
        _enabled = enabled;
        _blackScreen = blackScreen;

        if (!enabled || blackScreen || !hasVideo) {
            [self stopDecoderLocked];
            return;
        }

        if (!_decoderRunning || _sourceStamp != stamp) {
            if (now >= _retryAfter || _sourceStamp != stamp) {
                [self startDecoderLockedWithStamp:stamp];
            }
        }
    }
}

- (void)publishFrame:(CVPixelBufferRef)frame
           transform:(CGAffineTransform)transform
          generation:(NSUInteger)generation {
    CVPixelBufferRetain(frame);
    @synchronized (self) {
        if (!_decoderRunning || generation != _generation) {
            CVPixelBufferRelease(frame);
            return;
        }
        if (_latestFrame != NULL) {
            CVPixelBufferRelease(_latestFrame);
        }
        _latestFrame = frame;
        _frameTransform = transform;
    }
}

- (BOOL)waitForMediaTime:(CMTime)presentationTime
               firstTime:(CMTime *)firstTime
             playbackStart:(NSTimeInterval *)playbackStart
                generation:(NSUInteger)generation {
    if (!CMTIME_IS_VALID(presentationTime) || !CMTIME_IS_NUMERIC(presentationTime)) {
        return [self isGenerationActive:generation];
    }

    if (!CMTIME_IS_VALID(*firstTime)) {
        *firstTime = presentationTime;
        *playbackStart = CACurrentMediaTime();
    }

    const NSTimeInterval mediaElapsed = CMTimeGetSeconds(CMTimeSubtract(presentationTime, *firstTime));
    const NSTimeInterval deadline = *playbackStart + mediaElapsed;
    while ([self isGenerationActive:generation]) {
        const NSTimeInterval remaining = deadline - CACurrentMediaTime();
        if (remaining <= 0) {
            return YES;
        }
        [NSThread sleepForTimeInterval:MIN(remaining, 0.05)];
    }
    return NO;
}

- (void)decodeVideoAtPath:(NSString *)path generation:(NSUInteger)generation {
    while ([self isGenerationActive:generation]) {
        @autoreleasepool {
            AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
            NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            AVAssetTrack *track = tracks.firstObject;
            if (track == nil) {
                [self decoderDidFailForGeneration:generation];
                return;
            }

            NSError *error = nil;
            AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
            if (reader == nil || error != nil) {
                [self decoderDidFailForGeneration:generation];
                return;
            }

            NSDictionary *settings = @{
                (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
            };
            AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track
                                                                                outputSettings:settings];
            output.alwaysCopiesSampleData = NO;
            if (![reader canAddOutput:output]) {
                [self decoderDidFailForGeneration:generation];
                return;
            }
            [reader addOutput:output];
            if (![reader startReading]) {
                [self decoderDidFailForGeneration:generation];
                return;
            }

            CMTime firstTime = kCMTimeInvalid;
            NSTimeInterval playbackStart = 0;
            BOOL decodedAnyFrame = NO;

            while (reader.status == AVAssetReaderStatusReading && [self isGenerationActive:generation]) {
                CMSampleBufferRef sample = [output copyNextSampleBuffer];
                if (sample == NULL) {
                    break;
                }

                @autoreleasepool {
                    const CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sample);
                    if ([self waitForMediaTime:presentationTime
                                     firstTime:&firstTime
                                  playbackStart:&playbackStart
                                     generation:generation]) {
                        CVPixelBufferRef frame = CMSampleBufferGetImageBuffer(sample);
                        if (frame != NULL && [self isGenerationActive:generation]) {
                            [self publishFrame:frame transform:track.preferredTransform generation:generation];
                            decodedAnyFrame = YES;
                        }
                    }
                }
                CFRelease(sample);
            }

            if (reader.status == AVAssetReaderStatusReading) {
                [reader cancelReading];
            }
            if (reader.status == AVAssetReaderStatusFailed || !decodedAnyFrame) {
                if ([self isGenerationActive:generation]) {
                    [self decoderDidFailForGeneration:generation];
                    return;
                }
            }
            // A completed reader falls through and is recreated for a seamless loop.
        }
    }
}

- (BOOL)renderIntoPixelBuffer:(CVPixelBufferRef)targetBuffer {
    [self refreshConfigurationForced:NO];

    CVPixelBufferRef frame = NULL;
    CGAffineTransform frameTransform = CGAffineTransformIdentity;
    @synchronized (self) {
        if (!_enabled) {
            return NO;
        }
        if (!_blackScreen && _latestFrame != NULL) {
            frame = CVPixelBufferRetain(_latestFrame);
            frameTransform = _frameTransform;
        }
    }

    if (CVPixelBufferLockBaseAddress(targetBuffer, 0) != kCVReturnSuccess) {
        if (frame != NULL) {
            CVPixelBufferRelease(frame);
        }
        return YES;
    }

    @try {
        // Black is both the requested black-screen source and the failure-safe
        // output when a decoder has not produced a frame yet.
        OCFillPixelBufferBlack(targetBuffer);
        if (frame != NULL) {
            // Reader output does not apply a track's display rotation itself.
            CIImage *image = [[CIImage imageWithCVPixelBuffer:frame] imageByApplyingTransform:frameTransform];
            const CGRect extent = image.extent;
            const CGFloat targetWidth = CVPixelBufferGetWidth(targetBuffer);
            const CGFloat targetHeight = CVPixelBufferGetHeight(targetBuffer);
            if (extent.size.width > 0 && extent.size.height > 0 && targetWidth > 0 && targetHeight > 0) {
                image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,
                                                                                          -extent.origin.y)];
                const CGFloat scale = MAX(targetWidth / extent.size.width,
                                          targetHeight / extent.size.height);
                image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
                const CGRect scaledExtent = image.extent;
                const CGFloat offsetX = (targetWidth - scaledExtent.size.width) / 2.0 - scaledExtent.origin.x;
                const CGFloat offsetY = (targetHeight - scaledExtent.size.height) / 2.0 - scaledExtent.origin.y;
                image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(offsetX, offsetY)];
                image = [image imageByCroppingToRect:CGRectMake(0, 0, targetWidth, targetHeight)];
                [_imageContext render:image toCVPixelBuffer:targetBuffer];
            }
        }
    }
    @catch (__unused NSException *exception) {
        OCFillPixelBufferBlack(targetBuffer);
    }
    @finally {
        CVPixelBufferUnlockBaseAddress(targetBuffer, 0);
        if (frame != NULL) {
            CVPixelBufferRelease(frame);
        }
    }
    return YES;
}

@end
