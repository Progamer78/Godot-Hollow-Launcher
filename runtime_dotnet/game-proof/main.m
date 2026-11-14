#import <UIKit/UIKit.h>
#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/godot_view_controller.h"
extern int HollowRunGodotProof(const char *, const char *, const char *);
extern int HollowPrepareGodotGraphics(const char *, const char *, const char *);
extern const char *HollowGodotProofSavePath(void);

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
        fprintf(stderr, "HOLLOW_NATIVE_PROOF_START\n"); fflush(stderr);
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--hollow-graphics"]) {
            int result = HollowPrepareGodotGraphics(NSBundle.mainBundle.executablePath.UTF8String,
                [documents stringByAppendingPathComponent:@"game.pck"].UTF8String,
                [documents stringByAppendingPathComponent:@"godot.log"].UTF8String);
            if (result != 0) exit(1);
            GDTViewController *controller = [GDTViewController new];
            GDTAppDelegateService.viewController = controller;
            self.window.rootViewController = controller;
            NSString *proofPath = [NSString stringWithUTF8String:HollowGodotProofSavePath()];
            [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
                if ([NSFileManager.defaultManager fileExistsAtPath:proofPath]) {
                    NSData *data = [NSData dataWithContentsOfFile:proofPath];
                    [data writeToFile:[documents stringByAppendingPathComponent:@"graphics-proof.json"] atomically:YES];
                    NSDictionary *record = @{ @"native_result": @0 };
                    [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
                        writeToFile:[documents stringByAppendingPathComponent:@"native-result.json"] atomically:YES];
                    [timer invalidate];
                }
            }];
            return;
        }
        int result = HollowRunGodotProof(NSBundle.mainBundle.executablePath.UTF8String, [documents stringByAppendingPathComponent:@"game.pck"].UTF8String,
            [documents stringByAppendingPathComponent:@"godot.log"].UTF8String);
        fprintf(stderr, "HOLLOW_NATIVE_PROOF_RESULT: %d\n", result); fflush(stderr);
        NSDictionary *record = @{ @"native_result": @(result) };
        [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:[documents stringByAppendingPathComponent:@"native-result.json"] atomically:YES];
        exit(result);
    });
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(HollowGodotProofDelegate.class)); } }
