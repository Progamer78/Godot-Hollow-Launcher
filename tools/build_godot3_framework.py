"""Link the compiled Godot 3 archive as an isolated, bundled iOS framework."""
from pathlib import Path
import argparse
import json
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(engine, output):
    library = engine / "bin/libgodot.iphone.opt.arm64.a"
    if not library.is_file():
        raise RuntimeError(f"Missing Godot 3 ARM64 archive: {library}")
    framework = output / "Godot3Runtime.framework"
    framework.mkdir(parents=True, exist_ok=True)
    exports = output / "godot3-exports.txt"
    exports.write_text("_GP3GetAPI\n", encoding="utf-8")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    command = ["xcrun", "--sdk", "iphoneos", "clang++", "-dynamiclib", "-arch", "arm64", "-isysroot", sdk,
               "-miphoneos-version-min=15.0", "-Wl,-twolevel_namespace", "-Wl,-dead_strip",
               "-Wl,-force_load," + str(library.resolve()),
               "-Wl,-exported_symbols_list," + str(exports.resolve()),
               "-install_name", "@rpath/Godot3Runtime.framework/Godot3Runtime", "-lz", "-liconv", "-lresolv", "-lc++"]
    for name in ["Foundation", "CoreFoundation", "CoreGraphics", "CoreText", "UIKit", "QuartzCore", "OpenGLES", "AudioToolbox", "AudioUnit", "AVFoundation",
                 "CoreAudio", "CoreMedia", "CoreVideo", "CoreMotion", "CoreHaptics", "GameController",
                 "MediaPlayer", "Security", "SystemConfiguration"]:
        command += ["-framework", name]
    command += ["-o", str(framework / "Godot3Runtime")]
    subprocess.run(command, check=True)
    (framework / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.godotplayer.runtime.godot3", "CFBundleName": "Godot3Runtime",
        "CFBundleExecutable": "Godot3Runtime", "CFBundlePackageType": "FMWK",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "3.6.3", "MinimumOSVersion": "15.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
    }))
    for name in ["LICENSE.txt", "COPYRIGHT.txt", "AUTHORS.md"]:
        shutil.copy2(engine / name, framework / name)
    spine_notice = engine / "modules/spine_godot/LICENSE"
    if spine_notice.is_file():
        shutil.copy2(spine_notice, framework / "SPINE-RUNTIMES-LICENSE.txt")
    # Only the versioned bridge may be exported. C++ and Obj-C names must not
    # bind to the executable's Godot 4 engine. Also reject missing prefixes.
    symbols = subprocess.check_output(["xcrun", "nm", "-gUj", str(framework / "Godot3Runtime")], text=True).splitlines()
    if sorted(set(symbols)) != ["_GP3GetAPI"]:
        raise RuntimeError(f"Unexpected Godot 3 public exports: {symbols[:20]}")
    metadata = subprocess.check_output(["xcrun", "otool", "-ov", str(framework / "Godot3Runtime")], text=True)
    # Runtime class/protocol names still exist even when linker exports hide
    # their symbols. All engine-owned definitions must have the GP3 prefix.
    import re
    names = re.findall(r"^\s*name\s+0x[0-9a-f]+\s+(\w+)\s*$", metadata, re.MULTILINE)
    if not {"GP3GodotView", "GP3ViewController"}.issubset(names):
        raise RuntimeError("Could not verify Godot 3 Objective-C runtime metadata.")
    owned = json.loads((engine / "platform/iphone/player3-patch.json").read_text())["objc_names"]
    unprefixed = {name[3:] for name in owned} & set(names)
    if unprefixed:
        raise RuntimeError(f"Unprefixed runtime Objective-C names: {sorted(unprefixed)}")
    (output / "godot3-framework.json").write_text(json.dumps({"exports": symbols, "objc_prefix_audited": True, "runtime": "3.6.3", "framework": str(framework)}, indent=2) + "\n")
    print("Godot 3 framework linked; sole public symbol GP3GetAPI; Objective-C prefix audit passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.engine.resolve(), args.output.resolve())
