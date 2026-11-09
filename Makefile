ARCHS = arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = mediaserverd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OpenCamTweak
OpenCamTweak_FILES = Tweak.m FrameSource.m
OpenCamTweak_FRAMEWORKS = Foundation AVFoundation CoreMedia CoreVideo CoreImage CoreGraphics QuartzCore
OpenCamTweak_LIBRARIES = substrate roothide
OpenCamTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = OpenCam
OpenCam_FILES = main.m AppDelegate.m ViewController.m
OpenCam_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation AVKit Photos PhotosUI UniformTypeIdentifiers
OpenCam_LIBRARIES = roothide
OpenCam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
OpenCam_CODESIGN_FLAGS = -Sentitlements.plist
OpenCam_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
