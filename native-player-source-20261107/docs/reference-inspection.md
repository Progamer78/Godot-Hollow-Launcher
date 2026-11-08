# Reference findings and integration decisions

All required reference categories were examined before implementation: the GitHub workflow/export settings, successful build log, exported Xcode project and plist, supplied 4.7.2 template structure and libraries, and the game pack's header/directory/project signature.

- The successful log reports **4.7.stable.official.5b4e0cb0f**. Its setup action requests `4.7.0`, which maps to the `4.7-stable` release. The archive ends with `ARCHIVE SUCCEEDED`. The user reports real iPhone execution.
- The separate supplied template directory is **4.7.2**. The official release list was checked and still identified 4.7.2 as latest stable 4.x. Its source revision resolves to `ed1daf0bf001b61586d9930840f2f1394092c079`.
- The supplied game pack is 45,077,352 bytes, pack **format 4**, engine metadata **4.7.0**, flags **2** (relative file base), 243 directory entries. Its `project.binary` starts with `ECFG`. The exported-Xcode copy has the same size and header/directory. The template `data.pck` is an empty scaffold, not the reference game.
- The reference export bundles `<executable>.pck` as an Xcode resource, beside a statically linked `<executable>.xcframework`. The normal Godot project setup discovers this bundle pack when no explicit main pack is supplied.
- The supplied project uses Forward Plus, Jolt, seven autoloads, 1280×720 canvas stretching, iOS ARM64 and ETC2/ASTC imports. These are game settings, not launcher defaults; the player must load them from the selected pack.
- The workflow uses the standard editor/templates, no engine source modifications, unsigned `xcodebuild archive`, and manual Payload ZIP packaging. Its plist warnings concern empty camera/photo/microphone descriptions. The player removes those unused descriptions.
- The exported project has only generated plugin glue and dummy Swift/C++ files; startup is inside the engine archive. The reference Xcode plist uses the SwiftUI scene lifecycle. Replacing Xcode's dummy source would not by itself defer engine initialization.

Targeted source inspection of official 4.7.2 established this sequence:

```text
app.swift / SwiftUI UIApplicationDelegateAdaptor
  → GDTApplicationDelegate services
  → GDTAppDelegateService.didFinishLaunching
  → apple_embedded_main → OS_IOS → Main::setup(..., false)
  → ProjectSettings::_setup(main_pack) loads res://project.binary
GDTViewController / GDTViewRenderer
  → Main::setup2 → OS_AppleEmbedded::start → original main scene/autoloads
```

The implementation replaces the immediate SwiftUI game view with the library, moves the service's initialization body behind Play, and passes `--main-pack` to the unchanged `apple_embedded_main` path. It guards lifecycle callbacks before initialization and replays initial focus after setup2. `disable_path_overrides=no` is required because official release builds default to disabling the external main-pack argument. `get_user_data_dir` is redirected before setup to the selected UUID save directory; upstream otherwise returns Documents regardless of project name.

The PCK is mounted as the main project before resource settings, input maps, autoloads and scene startup. Imported contents are not changed. Rendering and gameplay run in Godot's existing native view. The adapter rejects a second initialization attempt; no teardown/restart claim is made.

The source patch also rejects native extension loading, rather than relying only on filename inspection or iOS signing failures. The launcher Swift code uses language mode 5, matching the reference Xcode target; the upstream Swift builder's mode is changed from 6 for those sources.

Primary sources consulted:

- [Official release history](https://github.com/godotengine/godot/releases)
- [Apple app entry](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/apple_embedded/app.swift), [delegate service](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/apple_embedded/app_delegate_service.mm), [iOS main](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/ios/main_ios.mm)
- [Project setup](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp), [pack reader](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/file_access_pack.cpp), [pack format constants](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/file_access_pack.h)
- [Exporting iOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html), [compiling iOS](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_ios.html), [packs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html), [command line](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
