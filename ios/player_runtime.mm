#import "PlayerRuntime.h"
#import "Godot3API.h"
#include <dlfcn.h>
#import "app_delegate_service.h"
#import "godot_app_delegate.h"
#import "godot_view_controller.h"
#import "godot_view_apple_embedded.h"
#include "drivers/apple_embedded/display_server_apple_embedded.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/os/keyboard.h"
#include "core/config/project_settings.h"
#include "core/object/class_db.h"
#include "core/string/print_string.h"
#include "modules/modules_enabled.gen.h"
#include "modules/player_tools/player_tools.h"
#ifdef MODULE_SPINE_GODOT_ENABLED
#include "modules/spine_godot/spine-cpp/include/spine/Version.h"
#endif
#import <QuartzCore/QuartzCore.h>

@interface GDTAppDelegateService (PlayerStart)
- (BOOL)startPlayerWithArguments:(NSArray<NSString *> *)arguments;
@end

// Set before Main::setup. Never changed within this process.
NSString *player_save_path = nil;
BOOL player_engine_ready = NO;
BOOL player_main_started = NO;
static NSString *requested_renderer;
static BOOL attempted = NO;
static const GP3API *godot3 = nullptr;
NSString *player_orientation = nil;
static NSMutableDictionary<NSString *, NSNumber *> *held_keys;
static NSMutableDictionary<NSNumber *, NSNumber *> *held_mouse;
static BitField<MouseButtonMask> mouse_buttons;
static BOOL mouse_enabled = NO;
static bool previous_mouse_from_touch = false;
static bool previous_touch_from_mouse = false;
static CFTimeInterval last_motion = 0;
static CFTimeInterval last_left_click = 0;
static Vector2 last_click_position;

@interface GDTApplicationDelegate (PlayerOrientation)
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window;
@end

@implementation GDTApplicationDelegate (PlayerOrientation)
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if ([player_orientation isEqualToString:@"portrait"]) return UIInterfaceOrientationMaskPortrait;
    if ([player_orientation isEqualToString:@"landscape"]) return UIInterfaceOrientationMaskLandscape;
    return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscape;
}
@end

static bool change_hold(NSMutableDictionary *holds, id key, BOOL pressed) {
    NSInteger count = [holds[key] integerValue];
    if (pressed) { holds[key] = @(count + 1); return count == 0; }
    if (count <= 0) return false;
    if (count == 1) { [holds removeObjectForKey:key]; return true; }
    holds[key] = @(count - 1);
    return false;
}

@implementation PlayerRuntime
+ (UIViewController *)startPack:(NSString *)packPath savePath:(NSString *)savePath renderer:(NSString *)renderer engineMajor:(NSInteger)major orientation:(NSString *)orientation error:(NSError **)error {
    NSAssert([NSThread isMainThread], @"Godot starts on the main thread");
    NSString *reason = nil;
    if (attempted) reason = @"A runtime has already started. Close the app from the app switcher and reopen it to select a game.";
    if (![[NSFileManager defaultManager] fileExistsAtPath:packPath]) reason = @"The imported PCK is missing.";
    if (reason) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];
        return nil;
    }
    attempted = YES;
    player_orientation = [orientation copy];
    if (major == 3) {
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"Godot3Runtime.framework/Godot3Runtime"];
        void *image = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        GP3GetAPIFunction getAPI = image ? (GP3GetAPIFunction)dlsym(image, "GP3GetAPI") : nullptr;
        const GP3API *api = getAPI ? getAPI() : nullptr;
        if (!api || api->version != 2) {
            const char *detail = dlerror();
            NSString *message = [NSString stringWithFormat:@"The bundled Godot 3 runtime could not load: %s. Make sure your signing tool signs embedded frameworks.", detail ?: "missing or incompatible runtime bridge"];
            if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:30 userInfo:@{NSLocalizedDescriptionKey:message}];
            return nil;
        }
        godot3 = api; // Deliberately retained until process exit; never dlclose.
        return godot3->start(packPath, savePath, renderer, orientation, error);
    }
    player_save_path = [savePath copy];
    requested_renderer = [renderer copy];
    held_keys = [NSMutableDictionary new];
    held_mouse = [NSMutableDictionary new];
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

+ (double)gameAspectRatio {
    if (godot3) return godot3->aspectRatio();
    if (!ProjectSettings::get_singleton()) return 16.0 / 9.0;
    double width = GLOBAL_GET("display/window/size/viewport_width");
    double height = GLOBAL_GET("display/window/size/viewport_height");
    if (width <= 0 || height <= 0) {
        width = GLOBAL_GET("display/window/size/window_width_override");
        height = GLOBAL_GET("display/window/size/window_height_override");
    }
    return width > 0 && height > 0 ? width / height : 16.0 / 9.0;
}

+ (NSString *)toolsRequest:(NSString *)json {
    NSAssert(NSThread.isMainThread, @"Game tools run on the engine thread");
    if (godot3) return godot3->tools(json);
    String response = PlayerTools::dispatch_json(String::utf8(json.UTF8String));
    return [NSString stringWithUTF8String:response.utf8().get_data()];
}

+ (void)logRuntimeConfiguration {
    print_line("Godot Player: requested renderer = " + String::utf8([requested_renderer UTF8String]));
#ifdef MODULE_SPINE_GODOT_ENABLED
    print_line("Godot Player: bundled Spine runtime = " SPINE_VERSION_STRING);
#else
    print_line("Godot Player: Spine runtime is not bundled");
#endif
    print_line(String("Godot Player: SpineSprite registered = ") + (ClassDB::class_exists("SpineSprite") ? "yes" : "no"));
    print_line(String("Godot Player: built-in LimboAI BTPlayer registered = ") + (ClassDB::class_exists("BTPlayer") ? "yes" : "no"));
    print_line("Godot Player: compiled GDScript tokenizer formats = 100, 101");
}

+ (NSString *)launchFailureMessage {
    // Read only a bounded tail; a large game's log must not be loaded whole.
    NSString *text = @"";
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:[player_save_path stringByAppendingPathComponent:@"player.log"]];
    if (handle) {
        @try {
            unsigned long long length = [handle seekToEndOfFile];
            [handle seekToFileOffset:length > 65536 ? length - 65536 : 0];
            text = [[NSString alloc] initWithData:[handle readDataOfLength:65536] encoding:NSUTF8StringEncoding] ?: @"";
        } @catch (NSException *exception) {
            text = @"";
        } @finally {
            [handle closeFile];
        }
    }
    NSString *reason = @"The game's main scene could not load. It may require missing resources, native classes, or a different runtime.";
    if ([text containsString:@"Binary GDScript"] || [text containsString:@"Unsupported binary GDScript tokenizer"]) {
        reason = @"This game's compiled scripts could not be read by the runtime. See player.log for the script format or parsing error.";
    } else if ([text containsString:@"Spine"] && ([text containsString:@"Cannot get class 'Spine"] || [text containsString:@"Could not find type \"Spine"] || [text containsString:@"SpineSkeletonDataResource' is not"])) {
        reason = ClassDB::class_exists("SpineSprite")
            ? @"The game's Spine animation resources could not load. Its exported Spine version may differ from the version bundled in this player."
            : @"This game requires the Spine animation runtime, which is not included in this player build. Changing the renderer cannot add the missing animation classes.";
    }
    return [reason stringByAppendingString:@" See player.log in the game's save folder for details. Close the app from the app switcher and reopen it before trying another game."];
}

+ (void)setKey:(NSString *)key pressed:(BOOL)pressed {
    if (godot3) { godot3->key(key, pressed); return; }
    if (!player_main_started) return;
    if (!Input::get_singleton() || !held_keys) return;
    if ([key isEqualToString:@"Mouse Left"]) { [self setMouseButton:1 pressed:pressed]; return; }
    if ([key isEqualToString:@"Mouse Right"]) { [self setMouseButton:2 pressed:pressed]; return; }
    if ([key isEqualToString:@"Mouse Middle"]) { [self setMouseButton:3 pressed:pressed]; return; }
    NSString *name = [key isEqualToString:@"Control"] ? @"Ctrl" : key;
    Key code = find_keycode(String::utf8([name UTF8String]));
    if (key.length == 1) code = (Key)[key.uppercaseString characterAtIndex:0];
    if (code == Key::NONE) return;
    if (!change_hold(held_keys, key, pressed)) return;
    Ref<InputEventKey> event;
    event.instantiate();
    event->set_keycode(code);
    event->set_physical_keycode(code);
    event->set_key_label(code);
    event->set_pressed(pressed);
    event->set_shift_pressed(held_keys[@"Shift"] != nil);
    event->set_ctrl_pressed(held_keys[@"Control"] != nil);
    event->set_alt_pressed(held_keys[@"Alt"] != nil);
    event->set_meta_pressed(held_keys[@"Meta"] != nil);
    if (key.length == 1) {
        NSString *text = held_keys[@"Shift"] ? key.uppercaseString : key.lowercaseString;
        event->set_unicode([text characterAtIndex:0]);
    } else if (code == Key::SPACE) {
        event->set_unicode(' ');
    }
    Input::get_singleton()->parse_input_event(event);
}

+ (void)releaseKeys {
    if (godot3) { godot3->releaseInputs(); return; }
    for (NSString *key in [held_keys allKeys]) { held_keys[key] = @1; [self setKey:key pressed:NO]; }
    for (NSNumber *button in [held_mouse allKeys]) { held_mouse[button] = @1; [self setMouseButton:button.integerValue pressed:NO]; }
}

+ (void)setMouseEnabled:(BOOL)enabled {
    if (godot3) { godot3->mouseEnabled(enabled); return; }
    if (!player_main_started) return;
    Input *input = Input::get_singleton();
    if (!input) return;
    if (mouse_enabled == enabled) {
        if (enabled) {
            input->set_emulate_mouse_from_touch(false);
            input->set_emulate_touch_from_mouse(false);
        }
        return;
    }
    [self releaseKeys];
    mouse_enabled = enabled;
    if (enabled) {
        last_motion = 0;
        previous_mouse_from_touch = input->is_emulating_mouse_from_touch();
        previous_touch_from_mouse = input->is_emulating_touch_from_mouse();
        input->set_emulate_mouse_from_touch(false);
        input->set_emulate_touch_from_mouse(false);
        UIView *view = GDTAppDelegateService.viewController.godotView;
        input->set_mouse_position(Vector2(view.bounds.size.width * view.contentScaleFactor / 2, view.bounds.size.height * view.contentScaleFactor / 2));
    } else {
        input->set_emulate_mouse_from_touch(previous_mouse_from_touch);
        input->set_emulate_touch_from_mouse(previous_touch_from_mouse);
    }
}

+ (void)moveMouse:(CGPoint)point fromView:(UIView *)source relative:(BOOL)relative {
    if (godot3) { godot3->moveMouse(point, source, relative); return; }
    if (!player_main_started) return;
    Input *input = Input::get_singleton();
    if (!input || !mouse_enabled) return;
    UIView *view = GDTAppDelegateService.viewController.godotView;
    if (!view || view.contentScaleFactor <= 0) return;
    CGFloat scale = view.contentScaleFactor;
    Vector2 old = input->get_mouse_position();
    CGPoint mapped = relative ? point : [view convertPoint:point fromView:source];
    Vector2 delta = relative ? Vector2(mapped.x * scale, mapped.y * scale) : Vector2(mapped.x * scale, mapped.y * scale) - old;
    Vector2 position = old + delta;
    if ([self mouseCaptured]) {
        position = Vector2(view.bounds.size.width * scale / 2, view.bounds.size.height * scale / 2);
    } else {
        position.x = CLAMP(position.x, 0, MAX(0, view.bounds.size.width * scale - 1));
        position.y = CLAMP(position.y, 0, MAX(0, view.bounds.size.height * scale - 1));
        delta = position - old;
    }
    Ref<InputEventMouseMotion> event;
    event.instantiate();
    event->set_position(position);
    event->set_global_position(position);
    event->set_relative(delta);
    event->set_relative_screen_position(delta);
    CFTimeInterval now = CACurrentMediaTime();
    Vector2 velocity = last_motion > 0 ? delta / MAX(0.001, now - last_motion) : Vector2();
    event->set_velocity(velocity);
    event->set_screen_velocity(velocity);
    last_motion = now;
    event->set_button_mask(mouse_buttons);
    input->set_mouse_position(position);
    input->parse_input_event(event);
}

+ (CGPoint)mousePositionInView:(UIView *)target {
    if (godot3) return godot3->mousePosition(target);
    if (!player_main_started) return CGPointZero;
    Input *input = Input::get_singleton();
    if (!input) return CGPointZero;
    UIView *view = GDTAppDelegateService.viewController.godotView;
    if (!view || view.contentScaleFactor <= 0) return CGPointZero;
    Vector2 position = input->get_mouse_position();
    return [target convertPoint:CGPointMake(position.x / view.contentScaleFactor, position.y / view.contentScaleFactor) fromView:view];
}

+ (void)setMouseButton:(NSInteger)button pressed:(BOOL)pressed {
    if (godot3) { godot3->mouseButton(button, pressed); return; }
    if (!player_main_started) return;
    Input *input = Input::get_singleton();
    if (!input || button < 1 || button > 3 || !held_mouse) return;
    if (!change_hold(held_mouse, @(button), pressed)) return;
    MouseButton value = (MouseButton)button;
    if (pressed) mouse_buttons.set_flag(mouse_button_to_mask(value)); else mouse_buttons.clear_flag(mouse_button_to_mask(value));
    Ref<InputEventMouseButton> event;
    event.instantiate();
    event->set_button_index(value);
    event->set_pressed(pressed);
    event->set_button_mask(mouse_buttons);
    event->set_position(input->get_mouse_position());
    event->set_global_position(input->get_mouse_position());
    event->set_shift_pressed(held_keys[@"Shift"] != nil);
    event->set_ctrl_pressed(held_keys[@"Control"] != nil);
    event->set_alt_pressed(held_keys[@"Alt"] != nil);
    event->set_meta_pressed(held_keys[@"Meta"] != nil);
    if (pressed && button == 1) {
        CFTimeInterval now = CACurrentMediaTime();
        bool double_click = last_left_click > 0 && now - last_left_click < 0.35 && last_click_position.distance_to(input->get_mouse_position()) < 24;
        event->set_double_click(double_click);
        last_left_click = double_click ? 0 : now;
        last_click_position = input->get_mouse_position();
    }
    input->parse_input_event(event);
}

+ (void)scrollMouse:(NSInteger)direction {
    if (godot3) { godot3->scroll(direction); return; }
    if (!player_main_started) return;
    Input *input = Input::get_singleton();
    if (!input) return;
    for (bool pressed : { true, false }) {
        Ref<InputEventMouseButton> event;
        event.instantiate();
        event->set_button_index(direction > 0 ? MouseButton::WHEEL_UP : MouseButton::WHEEL_DOWN);
        event->set_pressed(pressed);
        event->set_factor(1.0);
        event->set_button_mask(mouse_buttons);
        event->set_position(input->get_mouse_position());
        event->set_global_position(input->get_mouse_position());
        input->parse_input_event(event);
    }
}

+ (BOOL)mouseCaptured {
    if (godot3) return godot3->captured();
    if (!player_main_started) return NO;
    auto *display = DisplayServerAppleEmbedded::get_singleton();
    return display && display->player_get_effective_mouse_mode() == DisplayServerEnums::MOUSE_MODE_CAPTURED;
}

+ (BOOL)mouseCursorVisible {
    if (godot3) return godot3->cursorVisible();
    if (!player_main_started) return NO;
    auto *display = DisplayServerAppleEmbedded::get_singleton();
    if (!display) return NO;
    auto mode = display->player_get_effective_mouse_mode();
    return mode == DisplayServerEnums::MOUSE_MODE_VISIBLE || mode == DisplayServerEnums::MOUSE_MODE_CONFINED;
}

+ (NSUInteger)mouseCursorRevision {
    if (godot3) return 1;
    if (!player_main_started) return 0;
    auto *display = DisplayServerAppleEmbedded::get_singleton();
    return display ? display->player_get_cursor_revision() : 0;
}

+ (UIImage *)mouseCursorImage {
    if (godot3) return nil;
    if (!player_main_started) return nil;
    auto *display = DisplayServerAppleEmbedded::get_singleton();
    if (!display) return nil;
    Ref<Image> image = display->player_get_cursor_image();
    if (image.is_null()) return nil;
    Vector<uint8_t> png = image->save_png_to_buffer();
    NSData *data = [NSData dataWithBytes:png.ptr() length:png.size()];
    return [UIImage imageWithData:data scale:MAX(1.0, GDTAppDelegateService.viewController.godotView.contentScaleFactor)];
}

+ (CGPoint)mouseCursorHotspot {
    if (godot3) return CGPointZero;
    if (!player_main_started) return CGPointZero;
    auto *display = DisplayServerAppleEmbedded::get_singleton();
    if (!display) return CGPointZero;
    Vector2 hotspot = display->player_get_cursor_hotspot();
    CGFloat scale = MAX(1.0, GDTAppDelegateService.viewController.godotView.contentScaleFactor);
    return CGPointMake(hotspot.x / scale, hotspot.y / scale);
}
@end
