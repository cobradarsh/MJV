#import "AppDelegate.h"
#import "ViewController.h"

@implementation OCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[OCViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
