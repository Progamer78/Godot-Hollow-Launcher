#import "PlayerRuntime.h"
#import "app_delegate_service.h"
#import "godot_app_delegate.h"
#import "godot_view_controller.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/os/keyboard.h"
#include "core/config/project_settings.h"

@interface GDTAppDelegateService (PlayerStart)
- (BOOL)startPlayerWithArguments:(NSArray<NSString *> *)arguments;
@end

// Set before Main::setup. Never changed within this process.
NSString *player_save_path = nil;
BOOL player_engine_ready = NO;
static BOOL attempted = NO;
static NSMutableSet<NSString *> *held_keys;

@implementation PlayerRuntime
+ (UIViewController *)startPack:(NSString *)packPath savePath:(NSString *)savePath renderer:(NSString *)renderer error:(NSError **)error {
    NSAssert([NSThread isMainThread], @"Godot starts on the main thread");
    NSString *reason = nil;
    if (attempted) reason = @"A runtime has already started. Close the app from the app switcher and reopen it to select a game.";
    if (![[NSFileManager defaultManager] fileExistsAtPath:packPath]) reason = @"The imported PCK is missing.";
    if (reason) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];
        return nil;
    }
    attempted = YES;
    player_save_path = [savePath copy];
    held_keys = [NSMutableSet new];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        NSBundle.mainBundle.executablePath, @"--main-pack", packPath,
        @"--log-file", [savePath stringByAppendingPathComponent:@"player.log"]
    ]];
    if ([renderer isEqualToString:@"mobile"] || [renderer isEqualToString:@"gl_compatibility"]) {
        [arguments addObjectsFromArray:@[@"--rendering-method", renderer]];
    }
    BOOL started = NO;
    for (id service in [GDTApplicationDelegate services]) {
        if ([service isKindOfClass:[GDTAppDelegateService class]]) {
            started = [service startPlayerWithArguments:arguments];
            break;
        }
    }
    if (!started) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Godot project initialization failed. Close and reopen the app before trying again. See the game's Saves/player.log in Files."}];
        return nil;
    }
    if (String(GLOBAL_GET("application/run/main_scene")).is_empty()) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:3 userInfo:@{NSLocalizedDescriptionKey:@"The pack has no main scene. It may be an incomplete or resource-only project. Close and reopen the app."}];
        return nil;
    }
    player_engine_ready = YES;
    GDTViewController *controller = [GDTViewController new];
    GDTAppDelegateService.viewController = controller;
    return controller;
}

+ (void)setKey:(NSString *)key pressed:(BOOL)pressed {
    if (!Input::get_singleton() || !held_keys) return;
    if (pressed == [held_keys containsObject:key]) return;
    Key code = Key::NONE;
    if ([key isEqualToString:@"Up"]) code = Key::UP;
    else if ([key isEqualToString:@"Down"]) code = Key::DOWN;
    else if ([key isEqualToString:@"Left"]) code = Key::LEFT;
    else if ([key isEqualToString:@"Right"]) code = Key::RIGHT;
    else if ([key isEqualToString:@"Enter"]) code = Key::ENTER;
    else if ([key isEqualToString:@"Escape"]) code = Key::ESCAPE;
    else if ([key isEqualToString:@"Space"]) code = Key::SPACE;
    else if ([key isEqualToString:@"Shift"]) code = Key::SHIFT;
    else if ([key isEqualToString:@"Control"]) code = Key::CTRL;
    else if ([key isEqualToString:@"Tab"]) code = Key::TAB;
    else if (key.length == 1) code = (Key)[key.uppercaseString characterAtIndex:0];
    if (code == Key::NONE) return;
    if (pressed) [held_keys addObject:key]; else [held_keys removeObject:key];
    Ref<InputEventKey> event;
    event.instantiate();
    event->set_keycode(code);
    event->set_physical_keycode(code);
    event->set_pressed(pressed);
    event->set_shift_pressed([held_keys containsObject:@"Shift"]);
    event->set_ctrl_pressed([held_keys containsObject:@"Control"]);
    if (key.length == 1) event->set_unicode([key characterAtIndex:0]);
    Input::get_singleton()->parse_input_event(event);
}

+ (void)releaseKeys {
    for (NSString *key in [held_keys allObjects]) [self setKey:key pressed:NO];
}
@end
