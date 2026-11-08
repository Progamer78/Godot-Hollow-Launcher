import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class BuildToolsTests(unittest.TestCase):
    def test_patch_matches_official_release(self):
        names = [
            "drivers/apple_embedded/app.swift", "drivers/apple_embedded/app_delegate_service.mm",
            "drivers/apple_embedded/os_apple_embedded.mm", "drivers/apple_embedded/bridging_header_apple_embedded.h",
            "core/extension/gdextension.cpp", "platform_methods.py",
            "drivers/apple_embedded/godot_view_renderer.mm",
            "drivers/apple_embedded/godot_view_apple_embedded.mm",
        ]
        engine = ROOT / ".cache/godot-source"
        archive = ROOT / ".cache/source.zip"
        if not engine.is_dir() and not archive.is_file():
            self.skipTest("Official source checkout/archive unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            for name in names:
                path = target / name
                path.parent.mkdir(parents=True, exist_ok=True)
                if engine.is_dir():
                    shutil.copy2(engine / name, path)
                else:
                    with zipfile.ZipFile(archive) as source:
                        path.write_bytes(source.read("godot-4.7.2-stable/" + name))
            module("patch_engine").patch(target)
            service = (target / names[1]).read_text()
            self.assertIn("startPlayerWithArguments:", service)
            self.assertNotIn("exit(0)", service)
            self.assertEqual(service.count("if (!player_engine_ready || !OS_AppleEmbedded::get_singleton()) return;"), 12)
            self.assertIn("player_save_path", (target / names[2]).read_text())
            self.assertIn("Native game extensions are disabled", (target / names[4]).read_text())
            with self.assertRaises(RuntimeError):
                module("patch_engine").patch(target)

    def test_export_preparation_preserves_pipeline(self):
        with tempfile.TemporaryDirectory() as temporary:
            export = Path(temporary)
            library = export / "custom.a"
            library.write_bytes(b"custom-arm64-library")
            runtime = export / "player.xcframework/ios-arm64/libgodot.a"
            runtime.parent.mkdir(parents=True)
            runtime.write_bytes(b"official-library")
            app = export / "player"
            (app / "en.lproj").mkdir(parents=True)
            (app / "en.lproj/InfoPlist.strings").write_text("", encoding="utf-8")
            info = app / "player-Info.plist"
            info.write_bytes(plistlib.dumps({"NSCameraUsageDescription": "", "godot_cmdline": ["--main-pack", "wrong.pck"], "UIFileSharingEnabled": True}))
            (export / "player.pck").write_bytes(b"export scaffold")
            module("prepare_xcode").prepare(export, library)
            self.assertEqual(runtime.read_bytes(), library.read_bytes())
            data = plistlib.loads(info.read_bytes())
            self.assertTrue(data["UIFileSharingEnabled"])
            self.assertNotIn("NSCameraUsageDescription", data)
            self.assertNotIn("godot_cmdline", data)
            self.assertEqual((export / "player.pck").stat().st_size, 0)
            self.assertIn("Permission is hereby granted", (app / "en.lproj/InfoPlist.strings").read_text())


if __name__ == "__main__":
    unittest.main()
