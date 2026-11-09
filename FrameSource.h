#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@interface OCFrameSource : NSObject

+ (instancetype)sharedSource;
- (BOOL)renderIntoPixelBuffer:(CVPixelBufferRef)targetBuffer;
- (void)configurationDidChange;

@end
