"""Embed official Godot 3.6.3 in an isolated, bundled iOS framework."""
from pathlib import Path
import argparse
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
REVISION = "a3378686f7196db78d7b3cc7947f72a13bc4864c"


def replace(path, old, new):
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"Godot 3 patch anchor mismatch in {path.name}: {old[:70]}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


def patch(engine):
    ios = engine / "platform/iphone"
    marker = ios / "player3-patch.json"
    if marker.exists():
        raise RuntimeError("Use a clean Godot 3.6.3 source tree.")
    shutil.copytree(ROOT / "runtime_shared/player_tools", engine / "modules/player_tools")
    # Runtime registration of Objective-C classes/protocols is process-wide,
    # regardless of Mach-O symbol visibility. Prefix every engine-owned name.
    names = set()
    sources = []
    for folder in [engine / "platform/iphone", engine / "drivers", engine / "modules"]:
        for path in folder.rglob("*"):
            if path.suffix in (".m", ".mm", ".h"):
                text = path.read_text(encoding="utf-8", errors="strict")
                names.update(re.findall(r"@interface\s+(\w+)\s*:", text))
                names.update(re.findall(r"@protocol\s+(\w+)\s*(?:<|\n)", text))
                sources.append(path)
    # Direct token replacement also updates @class forward declarations and
    # string-based class references, without macro pollution of Apple headers.
    pattern = re.compile(r"\b(" + "|".join(sorted(names, key=len, reverse=True)) + r")\b")
    for path in sources:
        text = path.read_text(encoding="utf-8")
        updated = pattern.sub(lambda match: "GP3" + match.group(), text)
        if updated != text:
            path.write_text(updated, encoding="utf-8", newline="\n")
    scsub = ios / "SCsub"
    for name in ["main.m", "godot_app_delegate.m", "godot_scene_delegate.m"]:
        replace(scsub, f'    "{name}",\n', "")
    replace(scsub, '    "godot_iphone.mm",', '    "godot_iphone.mm",\n    "player3_runtime.mm",')
    for name in ["Godot3API.h", "player3_runtime.mm"]:
        shutil.copy2(ROOT / ("ios" if name.endswith(".h") else "runtime3") / name, ios / name)
    delegate = ios / "app_delegate.mm"
    replace(delegate, '#import "app_delegate.h"', '#import "app_delegate.h"\nextern NSString *gp3_save_path;')
    replace(delegate, 'NSString *documentsDirectory = [paths objectAtIndex:0];', 'NSString *documentsDirectory = gp3_save_path;')
    replace(delegate, '\t\texit(0);\n\t\treturn FALSE;', '\t\treturn FALSE;')
    replace(delegate, '\tself.window.rootViewController = viewController;', '\t// The SwiftUI host owns the only application window.')
    replace(delegate, '\t[self.window makeKeyAndVisible];', '\t// Return this controller to the existing host instead.')
    # Ignore export scaffolding arguments. Only the validated selected PCK may
    # choose the project; no Info.plist path can redirect it to a dummy project.
    bootstrap = ios / "godot_iphone.mm"
    replace(bootstrap, '\targc = add_path(argc, fargv);\n\targc = add_cmdline(argc, fargv);', '\t// Explicit player arguments only.')
    os_file = ios / "os_iphone.mm"
    replace(os_file, 'void OSIPhone::start() {\n\tMain::start();',
            'extern bool gp3_main_started;\nvoid OSIPhone::start() {\n\tgp3_main_started = Main::start();')
    anchor = 'Error OSIPhone::open_dynamic_library(const String p_path, void *&p_library_handle, bool p_also_set_library_path) {'
    replace(os_file, anchor, anchor + '\n\tERR_FAIL_V_MSG(ERR_UNAVAILABLE, "Godot Player does not load native game libraries.");')
    # Virtual cursor state must be visible to games querying OS/Input APIs.
    replace(ios / "os_iphone.h", 'virtual void set_mouse_show(bool p_show);',
            'MouseMode player_mouse_mode = MOUSE_MODE_VISIBLE;\n\tvirtual void set_mouse_mode(MouseMode p_mode) { player_mouse_mode = p_mode; }\n\tvirtual MouseMode get_mouse_mode() const { return player_mouse_mode; }\n\tvirtual void set_mouse_show(bool p_show);')
    replace(os_file, 'Point2 OSIPhone::get_mouse_position() const {\n\t// Not supported for iOS\n\treturn Point2();',
            'Point2 OSIPhone::get_mouse_position() const {\n\treturn input ? input->get_mouse_position() : Point2();')
    replace(os_file, 'int OSIPhone::get_mouse_button_state() const {\n\t// Not supported for iOS\n\treturn 0;',
            'int OSIPhone::get_mouse_button_state() const {\n\treturn input ? input->get_mouse_button_mask() : 0;')
    controller = ios / "view_controller.mm"
    replace(controller, '- (BOOL)shouldAutorotate {', '- (BOOL)shouldAutorotate {\n\treturn YES;')
    replace(controller, '- (UIInterfaceOrientationMask)supportedInterfaceOrientations {',
            '- (UIInterfaceOrientationMask)supportedInterfaceOrientations {\n\treturn UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscape;')
    renderer = ios / "godot_view_renderer.mm"
    replace(ios / "godot_view.mm", '[UIApplication sharedApplication].delegate.window.windowScene.interfaceOrientation',
            'self.window.windowScene.interfaceOrientation')
    replace(ios / "godot_view.mm", '- (void)startRendering {',
            '- (void)didMoveToWindow {\n'
            '\t[super didMoveToWindow];\n'
            '\tif (self.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) [self startRendering];\n'
            '\telse if (!self.window) [self stopRendering];\n}\n\n- (void)startRendering {')
    replace(ios / "godot_view.mm", '- (void)drawView {',
            '- (void)drawView {\n\tif (!self.window || self.bounds.size.width < 1 || self.bounds.size.height < 1) return;')
    replace(renderer, '#import "godot_view_renderer.h"',
            '#import "godot_view_renderer.h"\n#import "app_delegate.h"\n#import "view_controller.h"\nextern bool gp3_main_started;\nextern void gp3_render_ready();')
    replace(renderer, '@property(assign, nonatomic) BOOL hasFinishedSetup;',
            '@property(assign, nonatomic) BOOL hasFinishedSetup;\n@property(assign, nonatomic) BOOL playerFailed;\n- (void)playerFailure;')
    replace(renderer, '\t\texit(0);', '\t\t[self playerFailure];\n\t\treturn YES;')
    replace(renderer, '- (BOOL)setupView:(UIView *)view {', '- (BOOL)setupView:(UIView *)view {\n\tif (self.playerFailed) return YES;')
    replace(renderer, '\tMain::setup2();', '\tif (Main::setup2() != OK) { [self playerFailure]; return; }\n\tgp3_render_ready();')
    replace(renderer, '\t\tOSIPhone::get_singleton()->start();',
            '\t\tOSIPhone::get_singleton()->start();\n\t\tif (!gp3_main_started || !OS::get_singleton()->get_main_loop()) [self playerFailure];')
    # Two @end markers exist (private interface and implementation).
    text = renderer.read_text(encoding="utf-8")
    at = text.rfind("@end")
    text = text[:at] + '''- (void)playerFailure {
    self.playerFailed = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Godot 3 game could not start" message:@"See player.log in this game's save folder. Close and reopen the app before trying another game." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [GP3AppDelegate.viewController presentViewController:alert animated:YES completion:nil];
    });
}

''' + text[at:]
    renderer.write_text(text, encoding="utf-8", newline="\n")
    metadata = {"engine_revision": REVISION, "objc_names": sorted("GP3" + n for n in names), "export": "GP3GetAPI", "native_game_libraries": "blocked"}
    marker.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Godot 3 isolated framework patched; {len(names)} Objective-C names prefixed.")
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    patch(parser.parse_args().engine.resolve())
