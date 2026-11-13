#import <UIKit/UIKit.h>
extern int HollowRunGodotProof(const char *, const char *);

@interface HollowGodotProofDelegate : UIResponder <UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation HollowGodotProofDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new]; [self.window makeKeyAndVisible];
    // The pack is supplied to Documents after this app has already been built.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        int result = HollowRunGodotProof([documents stringByAppendingPathComponent:@"game.pck"].UTF8String,
            [documents stringByAppendingPathComponent:@"godot.log"].UTF8String);
        NSDictionary *record = @{ @"native_result": @(result) };
        [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:[documents stringByAppendingPathComponent:@"native-result.json"] atomically:YES];
        exit(result);
    });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(HollowGodotProofDelegate.class)); } }
