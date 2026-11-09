#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CydiaSubstrate.h>
#import "FrameSource.h"

// Private camera-graph class on iOS 16. Declaring the method locally avoids
// linking against private frameworks or headers.
@interface BWNodeOutput : NSObject
- (unsigned int)mediaType;
@end

static void (*OCOriginalEmitSampleBuffer)(id self, SEL selector, CMSampleBufferRef sampleBuffer);

static void OCEmitSampleBuffer(BWNodeOutput *self, SEL selector, CMSampleBufferRef sampleBuffer) {
    if (sampleBuffer != NULL && [self mediaType] == (unsigned int)'vide') {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pixelBuffer != NULL) {
            @try {
                [[OCFrameSource sharedSource] renderIntoPixelBuffer:pixelBuffer];
            }
            @catch (__unused NSException *exception) {
                // Always allow mediaserverd to deliver the original sample.
            }
        }
    }

    if (OCOriginalEmitSampleBuffer != NULL) {
        OCOriginalEmitSampleBuffer(self, selector, sampleBuffer);
    }
}

__attribute__((constructor)) static void OCInitializeTweak(void) {
    @autoreleasepool {
        Class outputClass = objc_getClass("BWNodeOutput");
        if (outputClass != Nil) {
            MSHookMessageEx(outputClass,
                            sel_registerName("emitSampleBuffer:"),
                            (IMP)&OCEmitSampleBuffer,
                            (IMP *)&OCOriginalEmitSampleBuffer);
        }
        (void)[OCFrameSource sharedSource];
    }
}
