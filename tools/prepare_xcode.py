"""Install the custom ARM64 adapter into an ordinary Godot iOS export."""
import argparse
from pathlib import Path
import plistlib
import shutil

ROOT = Path(__file__).resolve().parents[1]


def prepare(export, library, spine_license=None):
    notices = [
        ("GodotEngineNotices", (ROOT / "licenses/GODOT-LICENSE.txt").read_text(encoding="utf-8") + "\n" +
         (ROOT / "licenses/GODOT-COPYRIGHT.txt").read_text(encoding="utf-8")),
    ]
    if spine_license is not None:
        license_text = spine_license.read_text(encoding="utf-8")
        if "Spine Runtimes License Agreement" not in license_text:
            raise RuntimeError("Missing or invalid Spine runtime license notice.")
        notices.append(("SpineRuntimeNotices", license_text))
    # The known-working exporter creates this name from player.xcodeproj.
    target = export / "player.xcframework/ios-arm64/libgodot.a"
    if not target.is_file():
        raise RuntimeError(f"Expected official exported runtime at {target}")
    if not library.is_file():
        raise RuntimeError(f"Custom ARM64 runtime missing: {library}")
    shutil.copy2(library, target)
    info = export / "player/player-Info.plist"
    data = plistlib.loads(info.read_bytes())
    for permission in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"]:
        data.pop(permission, None)
    data["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
    data["UISupportedInterfaceOrientations~ipad"] = data["UISupportedInterfaceOrientations"]
    # No arbitrary exporter arguments may override the private selected pack.
    data.pop("godot_cmdline", None)
    data["CFBundleDocumentTypes"] = [{
        "CFBundleTypeName": "Godot Pack", "LSHandlerRank": "Alternate",
        "LSItemContentTypes": ["org.godotengine.pck"],
    }]
    data["UTImportedTypeDeclarations"] = [{
        "UTTypeIdentifier": "org.godotengine.pck", "UTTypeDescription": "Godot Resource Pack",
        "UTTypeConformsTo": ["public.data"], "UTTypeTagSpecification": {"public.filename-extension": ["pck"]},
    }]
    info.write_bytes(plistlib.dumps(data))
    # The scaffold exists only to obtain the upstream Xcode project. No launcher
    # project may accidentally become the game's main project at runtime.
    pack = export / "player.pck"
    if pack.is_file():
        pack.write_bytes(b"")
    # Already in the Resources build phase: add attribution without inventing
    # extra Xcode groups or changing engine/framework linker settings.
    strings = export / "player/en.lproj/InfoPlist.strings"
    with strings.open("a", encoding="utf-8") as out:
        for key, text in notices:
            escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            out.write('\n"' + key + '" = "' + escaped + '";\n')
    print(f"Prepared {export / 'player.xcodeproj'} with {library.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("export", type=Path)
    parser.add_argument("library", type=Path)
    parser.add_argument("--spine-license", type=Path)
    args = parser.parse_args()
    prepare(args.export.resolve(), args.library.resolve(), args.spine_license)
