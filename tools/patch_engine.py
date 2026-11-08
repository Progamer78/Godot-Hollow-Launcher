"""Apply narrowly anchored player changes to an unmodified 4.7.2 source tree."""
from pathlib import Path
import argparse
import shutil

ROOT = Path(__file__).resolve().parents[1]


def replace(path, old, new):
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"Expected exactly one patch anchor in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def patch(engine):
    apple = engine / "drivers/apple_embedded"
    if "import SwiftUI" not in (apple / "app.swift").read_text(encoding="utf-8"):
        raise RuntimeError("Expected an unmodified official Apple entry point; refusing to patch twice.")
    # Keep upstream's actual SwiftUI entry point, app delegate and render view.
    # Swap only its immediate game view for the native pack chooser.
    for source in (ROOT / "ios").iterdir():
        if source.suffix in (".swift", ".mm", ".h"):
            shutil.copy2(source, apple / source.name)
    app = apple / "app.swift"
    original = app.read_text(encoding="utf-8")
    app.write_text(original[:original.index("import SwiftUI")] + "// Entry point provided by PlayerApp.swift.\n", encoding="utf-8")
    with (apple / "bridging_header_apple_embedded.h").open("a", encoding="utf-8") as header:
        header.write('\n#import "PlayerRuntime.h"\n')
    # Match the exported Xcode target's Swift language mode. These launcher
    # sources use explicit dispatch queues and do not require Swift 6 isolation.
    replace(engine / "platform_methods.py", '"-swift-version",\n        "6",', '"-swift-version",\n        "5",')

    service = apple / "app_delegate_service.mm"
    replace(service, "int gargc;", "extern BOOL player_engine_ready;\nint gargc;")
    replace(service,
        "- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {",
        "- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {\n"
        "\t// Native library first; engine globals do not exist until Play.\n\treturn YES;\n}\n\n"
        "- (BOOL)startPlayerWithArguments:(NSArray<NSString *> *)arguments {")
    replace(service, "\tNSArray *arguments = [[NSProcessInfo processInfo] arguments];", "\t// Explicit, validated --main-pack supplied by the runtime adapter.")
    replace(service, "\t\texit(0);\n\t\treturn NO;", "\t\treturn NO; // Return a launch error to the native launcher.")
    replace(service, "malloc(sizeof(char *) * gargc)", "calloc(gargc + 1, sizeof(char *))")
    # Upstream callbacks assume its engine initialized during didFinishLaunching.
    # While the picker/library is showing there is intentionally no OS singleton.
    text = service.read_text(encoding="utf-8")
    for signature in [
        "- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application",
        "- (void)applicationWillTerminate:(UIApplication *)application",
        "- (void)onAudioInterruption:(NSNotification *)notification",
        "- (void)applicationWillResignActive:(UIApplication *)application",
        "- (void)applicationDidBecomeActive:(UIApplication *)application",
        "- (void)applicationDidEnterBackground:(UIApplication *)application",
        "- (void)applicationWillEnterForeground:(UIApplication *)application",
    ]:
        anchor = signature + " {"
        assert text.count(anchor) == 1, signature
        text = text.replace(anchor, anchor + "\n\tif (!player_engine_ready || !OS_AppleEmbedded::get_singleton()) return;")
    for name in ["sceneDidDisconnect", "sceneWillResignActive", "sceneDidBecomeActive", "sceneDidEnterBackground", "sceneWillEnterForeground"]:
        start = text.index("- (void)" + name + ":")
        brace = text.index("{", start)
        text = text[:brace+1] + "\n\tif (!player_engine_ready || !OS_AppleEmbedded::get_singleton()) return;" + text[brace+1:]
    service.write_text(text, encoding="utf-8", newline="\n")

    view = apple / "godot_view_apple_embedded.mm"
    for event in ["touchesBegan", "touchesMoved", "touchesEnded", "touchesCancelled"]:
        signature = f"- (void){event}:(NSSet *)touches withEvent:(UIEvent *)event {{"
        replace(view, signature, signature + "\n\tif (!DisplayServerAppleEmbedded::get_singleton()) return;")

    renderer = apple / "godot_view_renderer.mm"
    replace(renderer, '#import "godot_view_renderer.h"', '#import "godot_view_renderer.h"\n#import "app_delegate_service.h"')
    replace(renderer, "@property(assign, nonatomic) BOOL hasFinishedSetup;",
        "@property(assign, nonatomic) BOOL hasFinishedSetup;\n@property(assign, nonatomic) BOOL playerSetupFailed;")
    replace(renderer, "\tif (self.hasFinishedSetup) {", "\tif (self.playerSetupFailed) return YES;\n\tif (self.hasFinishedSetup) {")
    replace(renderer, "\tMain::setup2();",
        '\tif (Main::setup2() != OK) {\n\t\t[self playerFailed:@"Godot rendering or project setup failed. See player.log, then close and reopen the app."];\n\t\treturn;\n\t}\n'
        "\t// Play occurs after the scene became active; replay initial focus only\n"
        "\t// after audio and rendering subsystems have initialized.\n"
        "\tOS_AppleEmbedded::get_singleton()->on_focus_in();")
    replace(renderer, "\t\tOS_AppleEmbedded::get_singleton()->start();",
        '\t\tOS_AppleEmbedded::get_singleton()->start();\n'
        '\t\tif (!OS::get_singleton()->get_main_loop()) [self playerFailed:@"Godot could not start the main scene. See player.log, then close and reopen the app."];')
    replace(renderer, "- (void)renderOnView:(UIView *)view {",
        "- (void)renderOnView:(UIView *)view {\n\tif (self.playerSetupFailed) return;")
    replace(renderer, "\tOS_AppleEmbedded::get_singleton()->iterate();\n}\n\n@end",
        "\tOS_AppleEmbedded::get_singleton()->iterate();\n}\n\n" +
        '- (void)playerFailed:(NSString *)message {\n'
        '\tself.playerSetupFailed = YES;\n'
        '\tdispatch_async(dispatch_get_main_queue(), ^{\n'
        '\t\tUIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Game launch failed" message:message preferredStyle:UIAlertControllerStyleAlert];\n'
        '\t\t[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];\n'
        '\t\t[GDTAppDelegateService.viewController presentViewController:alert animated:YES completion:nil];\n'
        '\t});\n}\n\n@end')

    os_file = apple / "os_apple_embedded.mm"
    replace(os_file,
        "String OS_AppleEmbedded::get_user_data_dir(const String &p_user_dir) const {",
        "extern NSString *player_save_path;\n\n"
        "String OS_AppleEmbedded::get_user_data_dir(const String &p_user_dir) const {\n"
        "\tif (player_save_path) return String::utf8([player_save_path UTF8String]);")
    replace(os_file,
        "Error OS_AppleEmbedded::open_dynamic_library(const String &p_path, void *&p_library_handle, GDExtensionData *p_data) {",
        "Error OS_AppleEmbedded::open_dynamic_library(const String &p_path, void *&p_library_handle, GDExtensionData *p_data) {\n"
        '\tERR_FAIL_V_MSG(ERR_UNAVAILABLE, "Godot Player does not load native libraries from games.");')
    # Also block the GDExtension loader's RTLD_SELF entry-point path. No native
    # extensions are supported in this first, GDScript-only adapter.
    replace(engine / "core/extension/gdextension.cpp",
        "Error GDExtension::open_library(const String &p_path, const Ref<GDExtensionLoader> &p_loader) {",
        "Error GDExtension::open_library(const String &p_path, const Ref<GDExtensionLoader> &p_loader) {\n"
        '\tERR_FAIL_V_MSG(ERR_UNAVAILABLE, "Native game extensions are disabled in Godot Player.");')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("engine", type=Path)
    patch(parser.parse_args().engine.resolve())
