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
            "drivers/apple_embedded/display_server_apple_embedded.h",
            "drivers/apple_embedded/display_server_apple_embedded.mm",
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
            self.assertIn("player_main_started = Main::start() == EXIT_SUCCESS", (target / names[2]).read_text())
            renderer = (target / "drivers/apple_embedded/godot_view_renderer.mm").read_text()
            self.assertIn("!player_main_started || !OS::get_singleton()->get_main_loop()", renderer)
            self.assertIn("[PlayerRuntime launchFailureMessage]", renderer)
            self.assertIn("Native game extensions are disabled", (target / names[4]).read_text())
            display = (target / "drivers/apple_embedded/display_server_apple_embedded.h").read_text()
            self.assertEqual(display.count('#include "player_mouse_display.inc"'), 1)
            self.assertIn('#include "core/input/input.h"', display)
            self.assertTrue((target / "drivers/apple_embedded/GameControls.swift").is_file())
            self.assertTrue((target / "drivers/apple_embedded/ControlProfile.swift").is_file())
            self.assertTrue((target / "drivers/apple_embedded/player_mouse_display.inc").is_file())
            features = (target / "drivers/apple_embedded/display_server_apple_embedded.mm").read_text()
            for feature in ["FEATURE_MOUSE", "FEATURE_MOUSE_WARP", "FEATURE_CURSOR_SHAPE", "FEATURE_CUSTOM_CURSOR_SHAPE"]:
                self.assertIn("case DisplayServerEnums::" + feature + ":", features)
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
            notice = export / "SPINE-LICENSE.txt"
            notice.write_text("Spine Runtimes License Agreement\nPreserved notice", encoding="utf-8")
            module("prepare_xcode").prepare(export, library, notice)
            self.assertIn('"SpineRuntimeNotices"', (app / "en.lproj/InfoPlist.strings").read_text())
            self.assertIn("Preserved notice", (app / "en.lproj/InfoPlist.strings").read_text())
            notice.write_text("", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                module("prepare_xcode").prepare(export, library, notice)

    def test_bundled_spine_module_configuration(self):
        tool = module("prepare_spine")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            module_dir = source / "spine-godot/spine_godot"
            module_dir.mkdir(parents=True)
            registry = "\n".join("GDREGISTER_CLASS(" + c + ");" for c in tool.REQUIRED_CLASSES)
            for kind, name, server, role in [
                ("SpineAtlasResourceFormatLoader", "atlas_loader", "ResourceLoader", "loader"),
                ("SpineAtlasResourceFormatSaver", "atlas_saver", "ResourceSaver", "saver"),
                ("SpineSkeletonFileResourceFormatLoader", "skeleton_file_loader", "ResourceLoader", "loader"),
                ("SpineSkeletonFileResourceFormatSaver", "skeleton_file_saver", "ResourceSaver", "saver"),
            ]:
                registry += f"\nstatic {kind} *{name};\n{server}::remove_resource_format_{role}({name});"
            (module_dir / "register_types.cpp").write_text(registry)
            (module_dir / "SpineCommon.h").write_text('#include "core/error/error_macros.h"\n')
            (module_dir / "SpineSprite.h").write_text("uint32_t offsets[RS::ARRAY_MAX];\nRS::SurfaceData data;\nRS::ArrayFormat format;\nRS::get_singleton();\n")
            (module_dir / "SpineAnimationTrack.cpp").write_text("List<StringName> animation_libraries;\n\t\tanimation_player->get_animation_library_list(&animation_libraries);\n\t\tfor (auto iter = animation_libraries.front(); iter; iter = iter->next()) {\n\t\t\tanimation_player->remove_animation_library(iter->get());\n\t\t}")
            (module_dir / "SpineAtlasResource.cpp").write_text("JSON *json = memnew(JSON);\nmemdelete(json);\nmemdelete(json);\nJSON *json = memnew(JSON);\nmemdelete(json);")
            (module_dir / "SCsub").write_text('env.Append(CPPPATH=["#../spine_godot/spine-cpp/include"])\nenv_spine_runtime.Append(CPPPATH=["#../spine_godot/spine-cpp/include"])')
            header = source / "spine-cpp/spine-cpp/include/spine/Version.h"
            header.parent.mkdir(parents=True)
            header.write_text('#define SPINE_VERSION_STRING "4.2"')
            license_text = "Spine Runtimes License Agreement\nOriginal copyright notice"
            (source / "LICENSE").write_text(license_text)
            engine = root / "engine"
            report, notice = root / "report.json", root / "notice.txt"
            tool.prepare(engine, source, "4.2", report, notice, verify_revision=False)
            installed = engine / "modules/spine_godot"
            self.assertTrue((installed / "spine-cpp/include/spine/Version.h").is_file())
            self.assertEqual((installed / "LICENSE").read_text(), license_text)
            self.assertEqual(notice.read_text(), license_text)
            self.assertEqual((installed / "SCsub").read_text().count("#modules/spine_godot/spine-cpp/include"), 2)
            self.assertIn('#include "core/object/callable_mp.h"', (installed / "SpineCommon.h").read_text())
            self.assertIn('#include "servers/rendering/rendering_server.h"', (installed / "SpineCommon.h").read_text())
            adapted = (installed / "SpineSprite.h").read_text()
            self.assertIn("RenderingServerEnums::ARRAY_MAX", adapted)
            self.assertIn("RenderingServerTypes::SurfaceData", adapted)
            self.assertIn("RenderingServerEnums::ArrayFormat", adapted)
            self.assertIn("RenderingServer::get_singleton()", adapted)
            self.assertNotIn("RS::", adapted)
            self.assertIn("RS::ARRAY_MAX", (module_dir / "SpineSprite.h").read_text())
            self.assertIn("LocalVector<StringName> animation_libraries", (installed / "SpineAnimationTrack.cpp").read_text())
            self.assertNotIn("memdelete(json)", (installed / "SpineAtlasResource.cpp").read_text())
            self.assertEqual((installed / "register_types.cpp").read_text().count(".unref();"), 4)
            with self.assertRaises(RuntimeError):
                tool.prepare(engine, source, "4.2", report, notice, verify_revision=False)
            with self.assertRaises(RuntimeError):
                tool.prepare(root / "wrong-version", source, "4.1", report, notice, verify_revision=False)
            self.assertFalse((root / "wrong-version/modules/spine_godot").exists())

    def test_standard_build_can_exclude_spine(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module("prepare_spine").prepare(root / "engine", root / "unused", "none", root / "report.json", root / "notice.txt")
            self.assertFalse((root / "engine/modules/spine_godot").exists())
            self.assertFalse((root / "notice.txt").exists())


if __name__ == "__main__":
    unittest.main()
