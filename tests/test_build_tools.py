import importlib.util
from collections import Counter
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
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
    def test_godot3_navigation_objects_are_added_once(self):
        engine = ROOT / ".cache/godot3-source"
        relative = "modules/navigation/SCsub"
        if (engine / relative).is_file():
            original = (engine / relative).read_text()
        else:
            with zipfile.ZipFile(ROOT / ".cache/godot3-source.zip") as archive:
                original = archive.read("godot-3.6.3-stable/" + relative).decode()

        class Environment(dict):
            def __init__(self, recast, rvo):
                super().__init__(builtin_recast=recast, builtin_rvo2=rvo)
                self.modules_sources = []
                self.dependencies = []
            def Clone(self): return self
            def Prepend(self, **kwargs): pass
            def disable_warnings(self): pass
            def add_source_files(self, objects, sources):
                objects.extend([sources] if isinstance(sources, str) else sources)
            def Depends(self, objects, dependencies): self.dependencies = list(dependencies)

        def graph(source, recast, rvo):
            env = Environment(recast, rvo)
            exec(compile(source, relative, "exec"), {"Import": lambda *args: None, "env": env, "env_modules": env})
            return env

        broken = graph(original, True, True)
        duplicates = {name: count for name, count in Counter(broken.modules_sources).items() if count > 1}
        self.assertEqual(len(duplicates), 11, "Reproduce the 11 duplicated Recast objects in the supplied link failure")
        self.assertEqual(set(duplicates.values()), {2})
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            file = target / relative
            file.parent.mkdir(parents=True)
            file.write_text(original)
            module("patch_godot3").patch_navigation(target)
            repaired = file.read_text()
            for recast, rvo in [(True, True), (True, False), (False, True), (False, False)]:
                with self.subTest(recast=recast, rvo=rvo):
                    before = graph(original, recast, rvo)
                    after = graph(repaired, recast, rvo)
                    self.assertEqual(set(after.modules_sources), set(before.modules_sources), "Keep every enabled navigation source")
                    self.assertEqual(len(after.modules_sources), len(set(after.modules_sources)), "Each object must enter the archive once")
                    self.assertEqual(len(after.dependencies), (11 if recast else 0) + (2 if rvo else 0))
                    self.assertEqual(set(after.dependencies), set(after.modules_sources) - {"*.cpp"})

    def test_godot3_ios_plugin_callbacks_link(self):
        # Exercise the real C++ ABI and ARM64 Mach-O linker, including a
        # negative control that reproduces the two missing export callbacks.
        if sys.platform == "darwin":
            compiler = ["xcrun", "--sdk", "iphoneos", "clang++"]
            sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
            flags = ["-target", "arm64-apple-ios15.0", "-isysroot", sdk]
            linker = compiler + flags + ["-dynamiclib", "-Wl,-install_name,@rpath/PluginHooksProof.dylib"]
            nm = ["xcrun", "nm", "-u"]
        else:
            tools = ROOT / ".cache/llvm-mingw-20261104-ucrt-x86_64/bin"
            if not (tools / "clang++.exe").is_file():
                self.skipTest("ARM64 Mach-O compiler/linker unavailable")
            compiler = [str(tools / "clang++.exe")]
            flags = ["-target", "arm64-apple-ios15.0"]
            linker = [str(tools / "ld.lld.exe"), "-flavor", "darwin", "-dylib", "-arch", "arm64", "-platform_version", "ios", "15.0", "15.0", "-install_name", "@rpath/PluginHooksProof.dylib"]
            nm = [str(tools / "llvm-nm.exe"), "--undefined-only"]
        engine = ROOT / ".cache/godot3-source"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            api = root / "api"
            api.mkdir()
            for name in ["api.h", "api.cpp"]:
                if (engine / "platform/iphone/api" / name).is_file():
                    shutil.copy2(engine / "platform/iphone/api" / name, api / name)
                else:
                    with zipfile.ZipFile(ROOT / ".cache/godot3-source.zip") as archive:
                        (api / name).write_bytes(archive.read("godot-3.6.3-stable/platform/iphone/api/" + name))
            objects = [root / "api.o", root / "plugins.o"]
            sources = [api / "api.cpp", ROOT / "runtime3/player3_plugins.cpp"]
            for source, obj in zip(sources, objects):
                subprocess.run(compiler + flags + ["-DIPHONE_ENABLED", "-fvisibility=hidden", "-I", str(root), "-c", str(source), "-o", str(obj)], check=True, capture_output=True, text=True)
            image = root / "PluginHooksProof.dylib"
            failed = subprocess.run(linker + [str(objects[0]), "-o", str(image)], capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0, "The unchanged API must fail without export callbacks")
            self.assertIn("godot_ios_plugins_initialize", failed.stderr)
            self.assertIn("godot_ios_plugins_deinitialize", failed.stderr)
            subprocess.run(linker + [str(obj) for obj in objects] + ["-o", str(image)], check=True, capture_output=True, text=True)
            self.assertEqual(subprocess.check_output(nm + [str(image)], text=True).strip(), "", "Both callbacks must resolve without host-engine symbols")
            # Match the framework's force-load path, which reveals duplicates
            # that an ordinary archive search can leave unnoticed.
            ar = ["xcrun", "ar"] if sys.platform == "darwin" else [str(tools / "llvm-ar.exe")]
            duplicated = root / "duplicated.a"
            archive = root / "unique.a"
            subprocess.run(ar + ["qc", str(duplicated), str(objects[0]), str(objects[1]), str(objects[1])], check=True, capture_output=True)
            failed = subprocess.run(linker + ["-Wl,-force_load," + str(duplicated), "-o", str(image)] if sys.platform == "darwin" else linker + ["-force_load", str(duplicated), "-o", str(image)], capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("duplicate symbol", failed.stderr)
            subprocess.run(ar + ["qc", str(archive)] + [str(obj) for obj in objects], check=True, capture_output=True)
            force_load = ["-Wl,-force_load," + str(archive)] if sys.platform == "darwin" else ["-force_load", str(archive)]
            subprocess.run(linker + force_load + ["-o", str(image)], check=True, capture_output=True, text=True)
            self.assertEqual(subprocess.check_output(nm + [str(image)], text=True).strip(), "")

    def test_godot3_framework_link_and_audits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "engine"
            library = engine / "bin/libgodot.iphone.opt.arm64.a"
            library.parent.mkdir(parents=True)
            library.write_bytes(b"compiled-archive-fixture")
            for name in ["LICENSE.txt", "COPYRIGHT.txt", "AUTHORS.md"]:
                (engine / name).write_text(name)
            marker = engine / "platform/iphone/player3-patch.json"
            marker.parent.mkdir(parents=True)
            marker.write_text('{"objc_names":["GP3GodotView","GP3ViewController"]}')
            notice = engine / "modules/spine_godot/LICENSE"
            notice.parent.mkdir(parents=True)
            notice.write_text("Spine preserved notice")
            output = root / "output"
            tool = module("build_godot3_framework")
            responses = ["/test/iPhoneOS.sdk\n", "_GP3GetAPI\n",
                         "name 0x100 GP3GodotView\nname 0x200 GP3ViewController\n"]
            with mock_patch.object(tool.subprocess, "check_output", side_effect=responses), mock_patch.object(tool.subprocess, "run") as linker:
                tool.build(engine, output)
            command = linker.call_args.args[0]
            frameworks = [command[i + 1] for i, flag in enumerate(command) if flag == "-framework"]
            self.assertIn("AudioToolbox", frameworks)
            self.assertNotIn("AudioUnit", frameworks, "Audio Unit headers are present on iOS, but AudioToolbox supplies its link symbols")
            self.assertEqual(command[:4], ["xcrun", "--sdk", "iphoneos", "clang++"])
            self.assertEqual(command[command.index("-isysroot") + 1], "/test/iPhoneOS.sdk")
            self.assertIn("-Wl,-force_load," + str(library.resolve()), command)
            self.assertIn("-Wl,-twolevel_namespace", command)
            framework = output / "Godot3Runtime.framework"
            self.assertEqual(plistlib.loads((framework / "Info.plist").read_bytes())["MinimumOSVersion"], "15.0")
            self.assertEqual((framework / "SPINE-RUNTIMES-LICENSE.txt").read_text(), "Spine preserved notice")
            self.assertEqual((output / "godot3-exports.txt").read_text(), "_GP3GetAPI\n")
            with mock_patch.object(tool.subprocess, "check_output", side_effect=[responses[0], "_GP3GetAPI\n_leaked_engine_symbol\n"]), mock_patch.object(tool.subprocess, "run"):
                with self.assertRaisesRegex(RuntimeError, "Unexpected Godot 3 public exports"):
                    tool.build(engine, output)

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
            self.assertIn('"player3_plugins.cpp"', (ios / "SCsub").read_text())
            self.assertEqual((ios / "player3_plugins.cpp").read_bytes(), (ROOT / "runtime3/player3_plugins.cpp").read_bytes())
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
            "drivers/apple_embedded/SCsub",
            "drivers/sdl/joypad_sdl.cpp",
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
            # Execute the real patched SCsub with a tiny source-graph environment.
            # The archive must occur once under isolated flags; other drivers
            # retain their original module-enabled compilation environment.
            graph = []
            dependencies = []
            class DriverEnvironment(dict):
                drivers_sources = []
                def __init__(self, flags=()):
                    super().__init__(APPLE_PLATFORM="ios", APPLE_SDK_PATH="test-sdk")
                    self.flags = list(flags)
                def Clone(self): return DriverEnvironment(self.flags)
                def Append(self, **kwargs): self.flags.extend(kwargs.get("CCFLAGS", []))
                def Prepend(self, **kwargs): pass
                def add_source_files(self, output, sources):
                    names = [sources] if isinstance(sources, str) else [source.name for source in sources]
                    graph.extend((name, list(self.flags)) for name in names)
                    output.extend(["GameTools.o", "ToolModels.o"] if sources == "*.swift" else names)
                def Depends(self, targets, sources):
                    dependencies.extend((target, source.name) for target in targets for source in sources)
            class Node:
                abspath = "test-driver"
                def __init__(self, name): self.name = name
            source = (target / "drivers/apple_embedded/SCsub").read_text()
            body = "\n".join(line for line in source.splitlines() if not line.startswith("from "))
            def glob(pattern):
                names = {"*.mm": ["ArchiveSupport.mm", "PlayerRuntime.mm"],
                         "*.swift": ["GameTools.swift", "ToolModels.swift"],
                         "*.h": ["bridging_header_apple_embedded.h", "PlayerRuntime.h"],
                         "*.inc": ["ArchiveCore.inc"]}[pattern]
                return [Node(name) for name in names]
            exec(compile(body, "SCsub", "exec"), {
                "Import": lambda *args: None, "env": DriverEnvironment(), "Dir": Node,
                "Glob": glob,
                "setup_swift_builder": lambda *args: None,
            })
            archive_flags = [flags for name, flags in graph if name == "ArchiveSupport.mm"]
            self.assertEqual(len(archive_flags), 1)
            self.assertEqual(archive_flags[0][-2:], ["-fno-modules", "-fno-cxx-modules"])
            self.assertIn(("PlayerRuntime.mm", ["-fmodules", "-fcxx-modules"]), graph)
            self.assertIn(("*.swift", ["-fmodules", "-fcxx-modules"]), graph)
            self.assertIn(("GameTools.o", "ToolModels.swift"), dependencies)
            self.assertIn(("ToolModels.o", "GameTools.swift"), dependencies)
            self.assertIn(("GameTools.o", "bridging_header_apple_embedded.h"), dependencies)
            self.assertIn(("ToolModels.o", "PlayerRuntime.h"), dependencies)
            self.assertIn(("ToolModels.o", "ArchiveCore.inc"), dependencies)
            self.assertEqual({target for target, _ in dependencies}, {"GameTools.o", "ToolModels.o"})
            swift_targets = (target / "platform_methods.py").read_text()
            self.assertIn('target_suffix = "ios15.0"', swift_targets)
            self.assertIn('target_suffix = "ios15.0-simulator"', swift_targets)
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
            self.assertTrue((target / "drivers/apple_embedded/InputViews.swift").is_file())
            self.assertTrue((target / "drivers/apple_embedded/KeyboardInput.swift").is_file())
            self.assertTrue((target / "modules/player_tools/player_tools.cpp").is_file())
            self.assertTrue((target / "drivers/apple_embedded/player_mouse_display.inc").is_file())
            features = (target / "drivers/apple_embedded/display_server_apple_embedded.mm").read_text()
            for feature in ["FEATURE_MOUSE", "FEATURE_MOUSE_WARP", "FEATURE_CURSOR_SHAPE", "FEATURE_CUSTOM_CURSOR_SHAPE"]:
                self.assertIn("case DisplayServerEnums::" + feature + ":", features)
            with self.assertRaises(RuntimeError):
                module("patch_engine").patch(target)

    def test_archive_iphone_link_preflight(self):
        preflight = module("check_ios_archive_link")
        engine = Path("engine")
        output = Path("proof")
        steps = preflight.commands(engine, output, "iphone-sdk")
        self.assertEqual(len(steps), 5)
        compile_bridge, link = steps[-2:]
        for flag in ["-Os", "-fno-exceptions", "-fobjc-arc", "-fno-modules", "-fno-cxx-modules"]:
            self.assertIn(flag, compile_bridge)
        self.assertIn(str(engine / "drivers/apple_embedded/ArchiveSupport.mm"), compile_bridge)
        self.assertIn("arm64-apple-ios14.0", link)
        self.assertIn("-Wl,-undefined,error", link)
        self.assertNotIn("dynamic_lookup", " ".join(link))
        self.assertTrue(all(str(output / (name + ".o")) in link for name in ["ioapi", "unzip", "zip", "ArchiveSupport"]))
        self.assertEqual(compile_bridge[compile_bridge.index("-isysroot") + 1], "iphone-sdk")

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
            self.assertEqual(data["CFBundleDisplayName"], "Godot Hollow Launcher")
            self.assertEqual(data["MinimumOSVersion"], "15.0")
            declared = {item["UTTypeIdentifier"] for item in data["UTImportedTypeDeclarations"]}
            self.assertTrue({"org.godotengine.pck", "org.godotplayer.apk", "org.godotplayer.embedded-pack"}.issubset(declared))
            self.assertIn("org.godotplayer.apk", data["CFBundleDocumentTypes"][0]["LSItemContentTypes"])
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
            module("prepare_xcode").prepare(export, library, notice, compatibility_notice, "4.2")
            self.assertEqual(plistlib.loads(info.read_bytes())["HollowSpineRuntime"], "4.2")
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
