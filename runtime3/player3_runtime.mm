#import "Godot3API.h"
#import "app_delegate.h"
#import "view_controller.h"
#import "godot_view.h"
#include "os_iphone.h"
#include "core/os/keyboard.h"
#include "core/os/input_event.h"
#include "core/project_settings.h"
#include "core/script_language.h"
#include "modules/player_tools/player_tools.h"
#include <cstdlib>
#include <cstring>
#include <initializer_list>
#include <atomic>
#import <QuartzCore/QuartzCore.h>

@interface GP3AppDelegate (PlayerCreation)
- (void)createViewController;
@end

int gargc = 0;
char **gargv = nullptr;
NSString *gp3_save_path;
bool gp3_main_started = false;
static bool ready = false;
static bool attempted = false;
static std::atomic<bool> controller_override(false);
bool gp3_should_filter_controller() { return controller_override.load(); }
static BOOL configure_script_key(NSData *data) {
    if(attempted || (data && data.length!=32)) return NO;
    std::memset(script_encryption_key,0,32);
    if(data) std::memcpy(script_encryption_key,data.bytes,32);
    return YES;
}
static bool mouse_enabled = false;
static BOOL requested_mouse = NO;
static bool previous_mouse = false, previous_touch = false;
static NSMutableDictionary<NSString *, NSNumber *> *keys;
static NSMutableDictionary<NSNumber *, NSNumber *> *buttons;
static int button_mask = 0;
static double ratio = 16.0 / 9.0;
static CFTimeInterval last_motion = 0, last_click = 0;
static Vector2 last_click_point;

static InputDefault *input() { return static_cast<InputDefault *>(Input::get_singleton()); }
static void configure_controller(BOOL enabled) {
    if(controller_override.load()==bool(enabled)) return;
    if(enabled) controller_override.store(true);
    if(input()) {
        Array pads=input()->get_connected_joypads();
        for(int i=0;i<pads.size();i++) {
            int device=pads[i];
            for(int button=0;button<32;button++) input()->joy_button(device,button,false);
            for(int axis=0;axis<8;axis++) input()->joy_axis(device,axis,0);
        }
    }
    controller_override.store(enabled);
}
static bool hold(NSMutableDictionary *holds, id key, BOOL pressed) {
    NSInteger count = [holds[key] integerValue];
    if (pressed) { holds[key] = @(count + 1); return count == 0; }
    if (!count) return false;
    if (count == 1) { [holds removeObjectForKey:key]; return true; }
    holds[key] = @(count - 1); return false;
}

static void mouse_button(NSInteger button, BOOL pressed);
static void key(NSString *name, BOOL pressed) {
    if (!ready || !input()) return;
    if ([name isEqualToString:@"Mouse Left"]) { mouse_button(1, pressed); return; }
    if ([name isEqualToString:@"Mouse Right"]) { mouse_button(2, pressed); return; }
    if ([name isEqualToString:@"Mouse Middle"]) { mouse_button(3, pressed); return; }
    int code = find_keycode(String::utf8(name.UTF8String));
    if (name.length == 1) code = [name.uppercaseString characterAtIndex:0];
    if (!code || !hold(keys, name, pressed)) return;
    Ref<InputEventKey> event; event.instance();
    event->set_scancode(code); event->set_physical_scancode(code);
    event->set_pressed(pressed);
    event->set_shift(keys[@"Shift"] != nil); event->set_control(keys[@"Control"] != nil);
    event->set_alt(keys[@"Alt"] != nil); event->set_metakey(keys[@"Meta"] != nil);
    if (name.length == 1) event->set_unicode([(keys[@"Shift"] ? name.uppercaseString : name.lowercaseString) characterAtIndex:0]);
    else if (code == KEY_SPACE) event->set_unicode(' ');
    input()->parse_input_event(event);
}

static void release_inputs() {
    for (NSString *name in [keys allKeys]) { keys[name] = @1; key(name, NO); }
    for (NSNumber *value in [buttons allKeys]) { buttons[value] = @1; mouse_button(value.integerValue, NO); }
}

static void set_mouse_enabled(BOOL enabled) {
    requested_mouse = enabled;
    if (!ready || !input() || mouse_enabled == bool(enabled)) return;
    release_inputs(); mouse_enabled = enabled;
    if (enabled) {
        previous_mouse = input()->is_emulating_mouse_from_touch();
        previous_touch = input()->is_emulating_touch_from_mouse();
        input()->set_emulate_mouse_from_touch(false); input()->set_emulate_touch_from_mouse(false);
        UIView *view = GP3AppDelegate.viewController.godotView;
        input()->set_mouse_position(Vector2(view.bounds.size.width, view.bounds.size.height) * view.contentScaleFactor / 2);
    } else {
        input()->set_emulate_mouse_from_touch(previous_mouse); input()->set_emulate_touch_from_mouse(previous_touch);
    }
    last_motion = 0;
}

static BOOL captured() { return OS::get_singleton() && OS::get_singleton()->get_mouse_mode() == OS::MOUSE_MODE_CAPTURED; }
static BOOL visible() {
    if (!OS::get_singleton()) return NO;
    OS::MouseMode mode = OS::get_singleton()->get_mouse_mode();
    return mode == OS::MOUSE_MODE_VISIBLE || mode == OS::MOUSE_MODE_CONFINED;
}

static void move_mouse(CGPoint point, UIView *source, BOOL relative) {
    if (!ready || !mouse_enabled || !input()) return;
    UIView *view = GP3AppDelegate.viewController.godotView;
    CGFloat scale = MAX(1, view.contentScaleFactor);
    CGPoint mapped = relative ? point : [view convertPoint:point fromView:source];
    Vector2 old = input()->get_mouse_position();
    Vector2 delta = relative ? Vector2(mapped.x, mapped.y) * scale : Vector2(mapped.x, mapped.y) * scale - old;
    Vector2 position = old + delta;
    if (captured()) position = Vector2(view.bounds.size.width, view.bounds.size.height) * scale / 2;
    else {
        position.x = CLAMP(position.x, 0, MAX(0, view.bounds.size.width * scale - 1));
        position.y = CLAMP(position.y, 0, MAX(0, view.bounds.size.height * scale - 1));
        delta = position - old;
    }
    Ref<InputEventMouseMotion> event; event.instance();
    event->set_position(position); event->set_global_position(position);
    event->set_relative(delta); event->set_button_mask(button_mask);
    CFTimeInterval now = CACurrentMediaTime();
    event->set_speed(last_motion > 0 ? delta / MAX(0.001, now - last_motion) : Vector2());
    last_motion = now;
    input()->set_mouse_position(position); input()->parse_input_event(event);
}

static CGPoint mouse_position(UIView *target) {
    if (!ready || !input()) return CGPointZero;
    UIView *view = GP3AppDelegate.viewController.godotView;
    Vector2 position = input()->get_mouse_position();
    CGFloat scale = MAX(1, view.contentScaleFactor);
    return [target convertPoint:CGPointMake(position.x / scale, position.y / scale) fromView:view];
}

static void mouse_button(NSInteger button, BOOL pressed) {
    if (!ready || !input() || button < 1 || button > 3 || !hold(buttons, @(button), pressed)) return;
    int mask = 1 << (button - 1);
    if (pressed) button_mask |= mask; else button_mask &= ~mask;
    Ref<InputEventMouseButton> event; event.instance();
    event->set_button_index(button); event->set_button_mask(button_mask); event->set_pressed(pressed);
    event->set_position(input()->get_mouse_position()); event->set_global_position(input()->get_mouse_position());
    event->set_shift(keys[@"Shift"] != nil); event->set_control(keys[@"Control"] != nil);
    event->set_alt(keys[@"Alt"] != nil); event->set_metakey(keys[@"Meta"] != nil);
    if (button == 1 && pressed) {
        CFTimeInterval now = CACurrentMediaTime();
        bool twice = last_click > 0 && now - last_click < 0.35 && last_click_point.distance_to(input()->get_mouse_position()) < 24;
        event->set_doubleclick(twice); last_click = twice ? 0 : now; last_click_point = input()->get_mouse_position();
    }
    input()->parse_input_event(event);
}

static void scroll(NSInteger direction) {
    if (!ready || !input()) return;
    for (bool pressed : { true, false }) {
        Ref<InputEventMouseButton> event; event.instance();
        event->set_button_index(direction > 0 ? BUTTON_WHEEL_UP : BUTTON_WHEEL_DOWN);
        event->set_pressed(pressed); event->set_factor(1);
        event->set_button_mask(button_mask); event->set_position(input()->get_mouse_position());
        event->set_global_position(input()->get_mouse_position()); input()->parse_input_event(event);
    }
}

// Notification tokens retain these blocks for the lifetime of the selected
// runtime. The framework remains loaded until process exit; never dlclose it.
static void observe_lifecycle() {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
        if (ready) { release_inputs(); OSIPhone::get_singleton()->on_focus_out(); }
    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
        if (ready) OSIPhone::get_singleton()->on_focus_in();
        else if (GP3AppDelegate.viewController.godotView.window) [GP3AppDelegate.viewController.godotView startRendering];
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
        if (ready) OSIPhone::get_singleton()->on_enter_background();
    }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
        if (ready) OSIPhone::get_singleton()->on_exit_background();
    }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
        if (ready) [[GP3AppDelegate getSingleton] applicationDidReceiveMemoryWarning:UIApplication.sharedApplication];
    }];
}

void gp3_render_ready() {
    ready = true;
    set_mouse_enabled(requested_mouse);
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) OSIPhone::get_singleton()->on_focus_in();
    print_line("Godot Player: isolated Godot 3.6.3 runtime; external main PCK; native game libraries disabled.");
    print_line(String("Godot Player: Godot 3 SpineSprite registered = ") + (ClassDB::class_exists("SpineSprite") ? "yes" : "no"));
}

static UIViewController *start(NSString *pack, NSString *saves, NSString *renderer, NSString *orientation, NSError **error) {
    NSCAssert(NSThread.isMainThread, @"Godot 3 starts on main");
    if (attempted) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:31 userInfo:@{NSLocalizedDescriptionKey:@"Close and reopen the app before starting another game."}];
        return nil;
    }
    attempted = true; gp3_save_path = [saves copy]; keys = [NSMutableDictionary new]; buttons = [NSMutableDictionary new];
    NSArray<NSString *> *arguments = @[NSBundle.mainBundle.executablePath, @"--main-pack", pack, @"--log-file", [saves stringByAppendingPathComponent:@"player.log"]];
    gargc = (int)arguments.count; gargv = (char **)calloc(gargc + 1, sizeof(char *));
    for (int index = 0; index < gargc; index++) gargv[index] = strdup(arguments[index].UTF8String);
    GP3AppDelegate *delegate = [GP3AppDelegate getSingleton];
    if (![delegate application:UIApplication.sharedApplication didFinishLaunchingWithOptions:nil]) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:32 userInfo:@{NSLocalizedDescriptionKey:@"Godot 3 project setup failed. See player.log, then close and reopen the app."}];
        return nil;
    }
    if (String(GLOBAL_GET("application/run/main_scene")).empty()) {
        if (error) *error = [NSError errorWithDomain:@"GodotPlayer" code:33 userInfo:@{NSLocalizedDescriptionKey:@"This pack has no main scene. It may be incomplete or resource-only. Close and reopen the app."}];
        return nil;
    }
    if ([renderer isEqualToString:@"gles2"]) ProjectSettings::get_singleton()->set("rendering/quality/driver/driver_name", "GLES2");
    if ([renderer isEqualToString:@"gles3"]) ProjectSettings::get_singleton()->set("rendering/quality/driver/driver_name", "GLES3");
    double width = GLOBAL_GET("display/window/size/width"), height = GLOBAL_GET("display/window/size/height");
    if (width > 0 && height > 0) ratio = width / height;
    // Orientation is owned by the host. Rendering stays inside its fitted view.
    [delegate createViewController];
    observe_lifecycle();
    // The upstream view starts rendering once attached to the SwiftUI window;
    // setup2 must not run against a detached or zero-size GL framebuffer.
    return GP3AppDelegate.viewController;
}

static double aspect_ratio() { return ratio; }
static NSString *tools_request(NSString *json) {
    String response = PlayerTools::dispatch_json(String::utf8(json.UTF8String));
    return [NSString stringWithUTF8String:response.utf8().get_data()];
}
extern "C" __attribute__((visibility("default"))) const GP3API *GP3GetAPI() {
    static const GP3API api = {3, start, key, release_inputs, set_mouse_enabled, move_mouse, mouse_position, mouse_button, scroll, captured, visible, aspect_ratio, tools_request, configure_script_key, configure_controller};
    return &api;
}
