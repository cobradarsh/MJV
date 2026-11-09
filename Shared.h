#import <Foundation/Foundation.h>
#import <roothide.h>

static NSString * const OCChangeNotification = @"com.opencam.virtualcamera.changed";

// Media lives below the jailbreak root, matching RootHide's shared-data model.
static inline NSString *OCSharedDirectory(void) {
    return jbroot(@"/var/mobile/OpenCam");
}

static inline NSString *OCVideoPath(void) {
    return [OCSharedDirectory() stringByAppendingPathComponent:@"source.mp4"];
}

static inline NSString *OCBlackScreenPath(void) {
    return [OCSharedDirectory() stringByAppendingPathComponent:@"black-screen"];
}

// mediaserverd can always inspect this small marker without decoding the video.
static inline NSString *OCEnableDirectory(void) {
    return @"/var/mobile/Media/OpenCam";
}

static inline NSString *OCEnabledPath(void) {
    return [OCEnableDirectory() stringByAppendingPathComponent:@"enabled"];
}
