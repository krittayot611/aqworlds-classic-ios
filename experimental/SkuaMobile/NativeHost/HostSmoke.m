#import <UIKit/UIKit.h>
extern int aqw_host_run_check(const char *metadata, const char *documents);

@interface AQWNativeHostDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation AQWNativeHostDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 340, 300)];
    label.numberOfLines = 0;
    label.text = @"Testing native Mono hosting…";
    [controller.view addSubview:label];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    NSString *metadata = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"metadata"];
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        setenv("AQW_MONO_BUNDLE_PATH", [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"].UTF8String, 1);
        int status = aqw_host_run_check(metadata.UTF8String, documents.UTF8String);
        NSString *result = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:@"runtime-result.txt"]
                                                   encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ label.text = result ?: [NSString stringWithFormat:@"Host returned %d without a result", status]; });
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AQWNativeHostDelegate.class)); }
}
