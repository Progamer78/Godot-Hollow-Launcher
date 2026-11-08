import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
import zipfile
from unittest.mock import patch as mock_patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class BuildToolsTests(unittest.TestCase):
    def test_legacy_script_reader_and_builtin_limbo_staging(self):
        engine = ROOT / ".cache/godot-source"
        archive = ROOT / ".cache/source.zip"
        if not engine.is_dir() and not archive.is_file():
            self.skipTest("Official Godot 4 source unavailable")
        names = ["modules/gdscript/gdscript_tokenizer_buffer.h", "modules/gdscript/gdscript_tokenizer_buffer.cpp", "core/extension/gdextension_manager.cpp"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in names:
                target = root / "engine" / name; target.parent.mkdir(parents=True, exist_ok=True)
                if engine.is_dir(): shutil.copy2(engine / name, target)
                else:
                    with zipfile.ZipFile(archive) as z: target.write_bytes(z.read("godot-4.7.2-stable/" + name))
            source = root / "limbo"
            source.mkdir()
            (source / "SCsub").write_text("# LIMBOAI_MODULE\n")
            notice = "Copyright LimboAI\nPermission is hereby granted\n"
            (source / "LICENSE.md").write_text(notice)
            tool = module("prepare_compatibility")
            tool.prepare(root / "engine", source, root / "report.json", root / "notice.txt", verify_revision=False)
            generated = (root / "engine" / names[1]).read_text()
            self.assertIn("legacy_v100 ? 20 : 16", generated)
            self.assertIn("version != 100 && version != TOKENIZER_VERSION", generated)
            self.assertIn("token.type + 1", generated)
            self.assertIn("ERR_FAIL_COND_V(total_len < 5", generated)
            self.assertIn("token_count > uint32_t(total_len / 5)", generated)
            self.assertIn("len > uint32_t(total_len / 4)", generated)
            self.assertEqual((root / "notice.txt").read_text(), notice)
            self.assertIn("MODULE_LIMBOAI_ENABLED", (root / "engine" / names[2]).read_text())
            self.assertIn("imported library is not loaded", (root / "engine" / names[2]).read_text())
            with self.assertRaises(RuntimeError):
                tool.prepare(root / "engine", source, root / "report.json", root / "notice.txt", verify_revision=False)

    def test_godot3_patch_against_official_source(self):
        engine = ROOT / ".cache/godot3-source"
        archive = ROOT / ".cache/godot3-source.zip"
        if not (engine / "platform/iphone/SCsub").is_file() and not archive.is_file():
            self.skipTest("Official Godot 3 sources unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            if (engine / "platform/iphone/SCsub").is_file():
                for folder in ["platform/iphone", "drivers", "modules"]:
                    shutil.copytree(engine / folder, target / folder)
            else:
                with zipfile.ZipFile(archive) as z:
                    for name in z.namelist():
                        relative = name.removeprefix("godot-3.6.3-stable/")
                        if relative.startswith(("platform/iphone/", "drivers/", "modules/")) and not name.endswith("/"):
                            destination = target / relative
                            destination.parent.mkdir(parents=True, exist_ok=True)
                            destination.write_bytes(z.read(name))
            tool = module("patch_godot3")
            metadata = tool.patch(target)
            self.assertIn("GP3GodotView", metadata["objc_names"])
            self.assertIn("GP3GodotViewDelegate", metadata["objc_names"])
            self.assertTrue((target / "modules/player_tools/player_tools.cpp").is_file())
            ios = target / "platform/iphone"
            self.assertNotIn('"main.m"', (ios / "SCsub").read_text())
            self.assertIn('"player3_runtime.mm"', (ios / "SCsub").read_text())
            self.assertNotIn("exit(0)", (ios / "app_delegate.mm").read_text())
            self.assertIn("gp3_save_path", (ios / "app_delegate.mm").read_text())
            self.assertIn("gp3_main_started = Main::start()", (ios / "os_iphone.mm").read_text())
            self.assertIn("ERR_FAIL_V_MSG(ERR_UNAVAILABLE", (ios / "os_iphone.mm").read_text())
            self.assertNotIn("argc = add_cmdline(argc, fargv);", (ios / "godot_iphone.mm").read_text())
            self.assertIn("gp3_render_ready()", (ios / "godot_view_renderer.mm").read_text())
            self.assertIn("gp3_main_started", (ios / "godot_view_renderer.mm").read_text())
            self.assertNotIn("@interface GodotView :", (ios / "godot_view.h").read_text())
            with self.assertRaises(RuntimeError):
                tool.patch(target)

    def test_embedded_framework_collision_audit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / "Payload"
            app = payload / "player.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "player"}))
            framework = root / "Godot3Runtime.framework"
            framework.mkdir()
            (framework / "Godot3Runtime").write_bytes(b"test-image")
            installer = module("install_godot3_framework")
            host = "000 T _OBJC_CLASS_$_GDTViewController\n U _OBJC_CLASS_$_UIView\n"
            guest = "000 T _OBJC_CLASS_$_GP3ViewController\n U _OBJC_CLASS_$_UIView\n"
            with mock_patch.object(installer.subprocess, "check_output", side_effect=[host, guest]):
                installer.install(payload, framework)
            self.assertEqual((app / "Frameworks/Godot3Runtime.framework/Godot3Runtime").read_bytes(), b"test-image")
            with mock_patch.object(installer.subprocess, "check_output", side_effect=[host, host]):
                with self.assertRaises(RuntimeError):
                    installer.install(payload, framework)

    def test_patch_matches_official_release(self):
        names = [
            "drivers/apple_embedded/app.swift", "drivers/apple_embedded/app_delegate_service.mm",
            "drivers/apple_embedded/os_apple_embedded.mm", "drivers/apple_embedded/bridging_header_apple_embedded.h",
            "core/extension/gdextension.cpp", "platform_methods.py",
            "drivers/apple_embedded/godot_view_renderer.mm",
            "drivers/apple_embedded/godot_view_controller.mm",
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
            self.assertTrue((target / "modules/player_tools/player_tools.cpp").is_file())
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
            self.assertEqual(data["MinimumOSVersion"], "15.0")
            self.assertIn("UIInterfaceOrientationPortrait", data["UISupportedInterfaceOrientations"])
            self.assertNotIn("NSCameraUsageDescription", data)
            self.assertNotIn("godot_cmdline", data)
            self.assertEqual((export / "player.pck").stat().st_size, 0)
            self.assertIn("Permission is hereby granted", (app / "en.lproj/InfoPlist.strings").read_text())
            notice = export / "SPINE-LICENSE.txt"
            notice.write_text("Spine Runtimes License Agreement\nPreserved notice", encoding="utf-8")
            module("prepare_xcode").prepare(export, library, notice)
            self.assertIn('"SpineRuntimeNotices"', (app / "en.lproj/InfoPlist.strings").read_text())
            self.assertIn("Preserved notice", (app / "en.lproj/InfoPlist.strings").read_text())
            compatibility_notice = export / "limbo-license.txt"
            compatibility_notice.write_text("LimboAI MIT notice", encoding="utf-8")
            module("prepare_xcode").prepare(export, library, notice, compatibility_notice)
            self.assertIn("LimboAI MIT notice", (app / "en.lproj/InfoPlist.strings").read_text())
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
            tool.prepare(root / "engine3", source, "4.2", root / "report3.json", root / "notice3.txt", verify_revision=False, engine_major=3)
            self.assertIn("RS::ARRAY_MAX", (root / "engine3/modules/spine_godot/SpineSprite.h").read_text())
            self.assertEqual((root / "engine3/modules/spine_godot/SpineAtlasResource.cpp").read_text(), (module_dir / "SpineAtlasResource.cpp").read_text())
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
