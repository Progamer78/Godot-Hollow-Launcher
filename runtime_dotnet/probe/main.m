#import <UIKit/UIKit.h>
#include <mono/jit/jit.h>
#include <mono/metadata/assembly.h>
#include <stdint.h>
#include <stdlib.h>

extern int coreclr_initialize(const char *, const char *, int, const char **, const char **, void **, unsigned int *);
extern int coreclr_create_delegate(void *, unsigned int, const char *, const char *, const char *, void **);
extern void *mono_aot_module_System_Private_CoreLib_info;
extern void *mono_aot_module_HollowManagedProbe_info;

static void stage(NSString *message) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [message writeToFile:[documents stringByAppendingPathComponent:@"probe-stage.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stderr,"HOLLOW_MONO_STAGE %s\n",message.UTF8String);fflush(stderr);
}

static void record(BOOL passed, NSString *message) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSDictionary *result = @{ @"passed": @(passed), @"message": message, @"mode": @"MONO_AOT_MODE_INTERP", @"godot_game_execution": @NO };
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:[documents stringByAppendingPathComponent:@"probe-result.json"] atomically:YES];
    NSLog(@"HOLLOW_DOTNET_PROBE %@ %@", passed?@"PASS":@"FAIL",message);
    exit(passed?0:1);
}
static int native_callback(int value, int increment) { return value + increment; }

static void run_probe(void) {
    NSString *managed = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Managed"];
    NSMutableArray<NSString *> *assemblies = [NSMutableArray new];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:managed error:nil]) {
        if ([name.pathExtension isEqualToString:@"dll"]) [assemblies addObject:[managed stringByAppendingPathComponent:name]];
    }
    NSString *tpa = [assemblies componentsJoinedByString:@":"];
    const char *keys[] = {"TRUSTED_PLATFORM_ASSEMBLIES", "APP_PATHS", "APP_CONTEXT_BASE_DIRECTORY", "NATIVE_DLL_SEARCH_DIRECTORIES"};
    const char *values[] = {tpa.UTF8String, managed.UTF8String, managed.UTF8String, NSBundle.mainBundle.resourcePath.UTF8String};
    stage(@"Registering precompiled runtime trampolines");
    mono_aot_register_module(mono_aot_module_System_Private_CoreLib_info);
    mono_aot_register_module(mono_aot_module_HollowManagedProbe_info);
    // INTERP uses trampolines from the signed corelib image. INTERP_ONLY
    // still creates native wrappers at runtime and is unsuitable for iOS.
    mono_jit_set_aot_mode(MONO_AOT_MODE_INTERP);
    void *handle = NULL; unsigned int domain = 0;
    stage(@"Initializing runtime");
    int rc = coreclr_initialize("HollowManagedProbe", "Hollow", 4, keys, values, &handle, &domain);
    if (rc) record(NO, [NSString stringWithFormat:@"coreclr_initialize=%d",rc]);
    int (*add)(int,int) = NULL;
    stage(@"Obtaining native managed callback");
    rc = coreclr_create_delegate(handle,domain,"HollowManagedProbe","HollowManagedProbe","Add",(void **)&add);
    if (rc || !add || add(7,35)!=42) record(NO,[NSString stringWithFormat:@"managed native-entry callback failed: %d",rc]);
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *imported = [documents stringByAppendingPathComponent:@"IndependentGame.dll"];
    NSError *error = nil;
    if (![NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"IndependentGame.dll"] toPath:imported error:&error]) record(NO,error.localizedDescription);
    int (*load)(const char *, int (*)(int,int)) = NULL;
    stage(@"Loading independent Windows-x64 IL assembly after startup");
    rc = coreclr_create_delegate(handle,domain,"HollowManagedProbe","HollowManagedProbe","LoadGame",(void **)&load);
    if (rc || !load || load(imported.UTF8String,native_callback)!=42) record(NO,[NSString stringWithFormat:@"post-start DLL import/reverse callback failed: %d",rc]);
    record(YES,@"Interpreted .NET 8 assembly loaded after runtime startup; reflection, generics, LINQ, booleans and native callbacks passed. Godot integration is not established by this probe.");
}

@interface HollowMonoProbeDelegate : UIResponder <UIApplicationDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation HollowMonoProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{run_probe();});
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(HollowMonoProbeDelegate.class));} }
