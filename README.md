# Native Godot Player for iOS

The newest combined upload is **`build/checkpoints/GodotPlayer-Features-APK-Update.zip`**. It includes all earlier features, cosmetic changes and framework link repairs, plus APK/ZIP/embedded-PCK imports, save backups/transfers/preview, update review and safe launch, analog gamepad controls, text entry, shared control presets, toggle/repeat/chord buttons, expanded cheats, library organization and storage/support tools. [Feature coverage, usage limits, deferred work and exact validation](docs/player-improvements.md).

Upload every included folder at the existing repository root, including **.github**, **ios**, **tools**, **tests**, **runtime3**, **runtime_shared**, **bootstrap**, **samples** and **docs**. Run **Build native Godot Player**, Spine **4.2**. The patcher reports `imports-save-vault-controls-tools-v7`. Sign the app and embedded framework, then install with the same app identity to retain saves. **The new iOS UI/bridge/importer still needs Actions compilation and device testing; no new IPA has been produced here.** Both desktop engines compile and pass 66 native checks each; 16 Python/native helper tests pass. Native extraction plus the proposed APK pack layout executes the original sample games in both engines; the actual Swift APK packer is configured for macOS testing and remains unexecuted locally.

Previous build repair: the latest supplied Actions run compiles the Godot 3 archive and resolves its plugin callbacks, but linking exposes 75 duplicate Recast symbols. Godot 3.6.3's navigation SCsub adds the same 11 Recast objects twice when RVO2 is enabled. The patch now appends the combined third-party list once, preserving navigation sources/dependencies for all Recast/RVO2 configurations. Ten local tests pass, including real ARM64 force-load checks for duplicate archive members. The supplied official iOS template independently contains the same 75 duplicate symbols; extracting its Recast objects confirms that a single copy clears the duplicate-definition failure. These focused tests do not verify the complete repaired framework or IPA. Upload all contents of `GodotPlayer-Godot3-Link-Fix3.zip` over the previous combined update; earlier audio-link and plugin-callback fixes are included. `GodotPlayer-Compatibility-Cheats-Fixed3.zip` contains the refreshed combined upload, including cosmetic changes.

The preceding Godot 4/Spine player is reported working on iPhone. The user has not yet tried the Godot 3/joystick/portrait update. **The latest package includes that update, Captive Lili compatibility fixes, Godot 3 Spine support, and a live stats/cheats menu with an expression console. Its new iOS code still needs Actions compilation and device validation.** Both desktop runtimes compile and pass the native tools tests.

The launcher imports complete PCKs through Files and initializes the selected pack as Godot's **main project**. It does not mount games inside a Godot launcher project. The first adapter uses official Godot **4.7.2-stable**, revision `ed1daf0bf001b61586d9930840f2f1394092c079`.

Implemented source includes persistent UUID-based imports, directory validation, rename/delete, replacement while retaining saves, version metadata, runtime selection checks, renderer selection, editable key overlays, virtual mouse input, launch diagnostics, and a per-game `user://` path. Native rendering, audio, touch, keyboards, controller handling, and lifecycle continue through upstream Godot code.

Only one game can initialize per process. To choose another game, close the app from the iOS app switcher and reopen it. There is no subprocess, forced exit, simulated game execution, or assumed mobile restart API.

## Compatibility and cheats foundation

Extract `build/checkpoints/GodotPlayer-Features-APK-Update.zip` and upload **all its contents** at your existing GitHub repository root, preserving paths. Include **.github**, **bootstrap**, **ios**, **runtime3**, the new **runtime_shared**, **tools**, **tests**, **samples**, and **docs**. This combined package includes the previous untried update. Run **Build native Godot Player**, keeping Spine **4.2**. The patcher reports `imports-save-vault-controls-tools-v7`. Sign the IPA and embedded framework, then install over the existing app with the same identifier/identity to preserve saves. Requires iOS 15+.

Captive Lili's unchanged PCK now starts in a locally compiled Godot 4.7.2 runtime for 180 frames headlessly and with native OpenGL, with no script errors. Its old compiled-script format is translated in memory, and LimboAI is built into the engine. Full gameplay and iPhone rendering remain untested. Anomalous Coffee Machine remains blocked: its 96 encrypted game scripts do not decrypt with the standard engine key, despite matching the PCK checksums. The import error now explains that clearly; this player cannot run this encrypted copy. Godot 3 and Spine support alone cannot remove encryption.

While playing, open **⋯ → Game Tools · Cheats & Console**. Search for money, coins, health or other variable names, tap a value, and Apply. Nested dictionaries, arrays and script resources are supported. Pause/resume and guarded undo are included. The Console evaluates expressions against the scene root; it is not the editor's remote debugger. Edits persist when the game saves. Availability depends on how the game stores its state. See [usage, validation and remaining limits](docs/game-tools.md).

Both complete Windows release runtimes compiled with the shared tools module. **66 native checks passed in each engine (132 total)**, including the JSON bridge, 64-bit values/IDs, nested edits, undo, pause, expressions and stale/type-changed objects. Sixteen Python/native helper tests pass. The new Swift UI/model/inspector cases and ARM64 builds must run in Actions; no new IPA has been produced locally.

## Godot 3, joysticks and portrait update

These features are included in the latest combined package above. Both engines are bundled at build time; import packs after installation as before. Do not upload reference games or templates.

Godot 3 uses a separate bundled `Godot3Runtime.framework`, selected automatically for a Godot 3 PCK. The framework exports one versioned UIKit bridge, hides engine symbols, prefixes Objective-C classes/protocols, and stays loaded for the process lifetime. Godot 4 retains its existing engine image. Neither engine is downloaded by the app. Native libraries from imported games remain disabled. See [Godot 3 implementation and validation](docs/godot3.md).

While playing, open the menu, then **Edit Controls**, then **Add Joystick**. Choose **Fixed** or **Floating**, arrow keys/WASD or individual direction mappings, size and deadzone; tap **Apply**, then **Save**. Drag a fixed joystick in the layout editor to position it. Floating mode appears at a touch and handles drags across the control area; buttons and the menu stay above it. It reserves those drags, so mouse mode is off. Turning mouse mode on changes a floating joystick to fixed without deleting its settings. **Hide Controls** hides buttons and the stick together.

Before Play, choose **Portrait (Fit)**, **Landscape**, or **Rotate automatically** under **Orientation** in game details. Portrait fits the original game aspect ratio inside the available view with no cropping. Landscape uses the existing full rendering area. The original game pack and its project settings are not rewritten. Orientation is saved per game; iOS rotation lock can still affect automatic rotation. The minimum device OS is now iOS 15.

Sign and install using the same app identifier/identity as the working version. Your signing tool must sign **embedded frameworks**, including `Godot3Runtime.framework`. Install over the existing app to retain the library and saves. Test a Godot 4 game first, then close/reopen the process and import `Sadiubus_x64.pck`; no rebuild is needed between games. The build artifact also includes an original Godot 3 test PCK with input/animation/save checks. Both runtimes must pass on the same installed IPA before multi-version device support is considered verified.

## Verified locally on Windows

- Official Godot 4.7.2 Windows executable checksum verified against release metadata.
- Two separate original projects exported to standalone PCKs and executed using `--main-pack` from an empty working directory.
- Both executed with headless rendering and with native OpenGL graphics windows; GDScript input, animation, autoload, and save/load checks passed.
- Each game loaded its previous saved value on another launch.
- Supplied `I Can Smell You From Here.pck` initialized headlessly, reported 97 dialogue nodes and successful game-data validation, then exited normally. Its gameplay was not tested.
- Python build-tool tests pass against the actual official release sources and an export-preparation fixture.

The earlier macOS GitHub Actions runs compiled the Swift pack inspector and passed all 253 original checks, including malformed/truncated files and the real sample packs. Both desktop PCK proofs also passed on macOS. After the export fixes, the user reports that two games work on the actual iPhone. Specific save-isolation, controller, and lifecycle scenarios still need separate device verification. Swift checks run in macOS CI. New cases cover old control-profile migration, joystick persistence/deadzones, runtime-major selection and portrait fitting; these new Swift cases have not run from Windows.

The unmodified Pokémon Battle Advanced 0.3.3 PCK also reached its boot scene on Windows Godot 4.7.2 with no script/parse errors, using headless and graphical Compatibility runs. Its unavailable WebRTC backend and shutdown errors remain in the logs. This establishes desktop startup, not complete gameplay or iPhone compatibility.

See [test evidence](tests/results/validation.md), [reference inspection](docs/reference-inspection.md), and [remaining compatibility work](docs/compatibility.md).

## Build through GitHub Actions

1. Put these project files in a GitHub repository. Do not upload `GodotPlayerReference/`, `.cache/`, credentials, or generated `build/` files. The reference materials remain untouched locally.
2. Open **Actions → Build native Godot Player → Run workflow**. A push to `main` or `master` also runs it.
3. Leave **Bundled Spine version** at **4.2** for Goodbye Eternity 0.14.1. The workflow obtains matching official editor/templates, tests two packs, checks out immutable engine/Spine revisions, applies the source changes, and builds its ARM64 static library. The Spine runtime is compiled into the IPA, never loaded from imported games. The `none` option retains a standard build without Spine.
4. It uses the reference's existing `godot --export-release → xcodebuild archive → Payload ZIP` sequence. The custom runtime replaces only the exported ARM64 library. Exported framework links and Xcode source structure are preserved.
5. Download `GodotPlayer-build-and-tests`. A successful archive includes `GodotPlayer-unsigned.ipa`, both sample PCKs, and logs.

For the current update, use the Godot 3 / joystick / portrait upload instructions above. The patch step reports `dual-runtime-joystick-portrait-v5`.

Sign the new IPA with the same app identifier and sideloading identity as the installed player, then install it as an update. Avoid uninstalling the existing app if you want to retain its library and saves.

If the Spine build failed with missing `callable_mp` / `RS` declarations, use `build/checkpoints/GodotPlayer-Spine-Build-Fix.zip`. Upload its **tools** and **tests** folders at the repository root, keeping files inside those folders, then run the same workflow with Spine **4.2**. The staging step must print `Spine engine adaptation: godot-4.7-module-api-v1`. The fix adapts the pinned Spine source to Godot 4.7's explicit headers, rendering namespaces, animation-library container, and reference-counted allocation rules. All 100 Spine C++ files and a complete Godot 4.7.2 Windows runtime compiled locally. That runtime started the unchanged Goodbye Eternity Mac PCK for 90 headless frames, exit 0 with zero script errors. This does not establish an iOS archive/device result.

## Mouse and saved controls

While a game is running, tap the small **⋯** button to open controls. It starts collapsed, has no permanent bar, and can be dragged away from the game's own buttons; its location persists. Only the button and an explicitly opened panel occupy touch space. The panel does not change the game's rendering area or the control canvas. Toggling mouse/visibility/mode closes it automatically.

Choose **Edit Controls**. Drag a button to move it; tap it to change its label, keyboard/mouse input, or size. **Add Button** adds another mapping. **Apply** updates that button in the draft; **Save** stores the entire layout for this game. **Cancel** discards the draft. Existing layouts, game identities, and save folders are preserved.

Tap **Mouse: Off** to enable the pointer. **Trackpad** uses relative finger movement and a tap for left click. Tap **Trackpad** to switch to **Direct Touch**, where a finger positions the pointer and presses the left button for dragging. Dedicated **Left Click**, **Right Click**, and scroll buttons remain available in the expanded panel. Mouse click buttons can also be added to a saved layout. Captured mouse games receive relative movement and control whether their cursor is visible. Turn the mouse off to restore native game touch input. Mouse settings and button visibility save per game.

For Pokémon Battle Advanced, import the original complete `.pck` again, open its details, enable **Try without native extensions**, then press Play. The previous importer rejected the optional `webrtc_native.gdextension` descriptor outright. The new importer records a warning instead. No imported native code is loaded, and the pack stays unchanged. Online WebRTC features are unavailable; a game requiring native classes may still fail. This Pokémon launch path has not yet been tested on an iPhone.

## Goodbye Eternity / Spine

The supplied Goodbye Eternity 0.14.1 packs identify Godot 4.6.1 and contain Spine 4.2 animation data. Both iPhone logs fail on missing Spine classes and the splash scene; both use Compatibility rendering. The 2 GB archive size is not the failure shown in those logs.

The unchanged Windows embedded pack and Mac standalone PCK both start headlessly with zero script errors in the official Spine 4.2-enabled Godot 4.6.1 desktop build. Standard Godot 4.7.2 reproduces the missing-class failure. The player now stages the real official Spine 4.2 C++ module into its Godot 4.7.2 source build. This fixes the missing dependency in source; compilation and actual iPhone execution remain to be verified. Do not expect arbitrary native plugins to work.

The startup check now retains `Main::start()`'s actual result. A failed main scene displays a launch error instead of being mistaken for a running game because a main-loop object exists. New logs also identify the requested renderer and bundled Spine version.

Spine uses a [separate runtime license](https://github.com/EsotericSoftware/spine-runtimes/blob/4.2/LICENSE), not Godot's MIT license. Its integration/distribution terms require appropriate Spine licensing; see the upstream terms before building or distributing a Spine-enabled player. Original notices are preserved in downloaded sources and included in the IPA resources and build artifact. The workflow can select 4.1/4.2/4.3, but the tested game requires **4.2**; later Spine minor versions do not automatically read older exports. Only one Spine minor version is currently bundled in an IPA.

The engine rebuild is necessary: official release templates default to disabling external main-pack overrides, initialize before a game can be selected, and share one Documents save path. It is an application-runtime build, performed once per player version, not once per imported game.

## Build manually on macOS

Use Xcode with the iOS SDK and Python 3. Install the **4.7.2 standard editor and official export templates**. Put the editor's executable on PATH as `godot`, then run from this repository:

```sh
mkdir -p .cache build/ios
git clone https://github.com/godotengine/godot.git .cache/godot-source
git -C .cache/godot-source checkout ed1daf0bf001b61586d9930840f2f1394092c079
git clone --filter=blob:none --sparse https://github.com/EsotericSoftware/spine-runtimes.git .cache/spine-runtimes
git -C .cache/spine-runtimes sparse-checkout set spine-godot/spine_godot spine-cpp/spine-cpp
git -C .cache/spine-runtimes fetch --depth 1 origin 5cb78e77d3711ddcd80c7bd043bb11cf70fcc88c
git -C .cache/spine-runtimes checkout --detach FETCH_HEAD
python3 tools/prepare_spine.py .cache/godot-source .cache/spine-runtimes --version 4.2
python3 tools/desktop_proof.py "$(command -v godot)"
swiftc -swift-version 5 ios/PCKInspector.swift tests/pck/main.swift -o build/pck-tests
build/pck-tests build/proof/movement.pck build/proof/counter.pck
swiftc -swift-version 5 ios/PCKInspector.swift ios/ControlProfile.swift ios/GameLibrary.swift tests/models/main.swift -o build/model-tests
build/model-tests
python3 -m unittest discover -s tests -v
python3 tools/patch_engine.py .cache/godot-source
python3 -m venv .cache/scons-env
.cache/scons-env/bin/pip install scons==4.10.1
cd .cache/godot-source
../scons-env/bin/scons platform=ios target=template_release arch=arm64 \
  disable_path_overrides=no vulkan=no metal=yes opengl3=yes \
  debug_symbols=no optimize=size -j"$(sysctl -n hw.logicalcpu)"
cd ../..
godot --headless --path bootstrap --editor --import
godot --headless --path bootstrap --export-release iOS "$PWD/build/ios/player.xcodeproj"
python3 tools/prepare_xcode.py build/ios .cache/godot-source/bin/libgodot.ios.template_release.arm64.a --spine-license build/SPINE-RUNTIMES-LICENSE.txt
open build/ios/player.xcodeproj
```

The generated Xcode project is the reproducible project configuration. `bootstrap/` exists only to obtain the official export; its pack is emptied during preparation and is never a fallback game. Reapply patches to a **clean** engine checkout after source changes; the patcher rejects repeated application.

The initial custom build contains Metal and OpenGL ES. Vulkan is disabled to avoid rebuilding MoltenVK; the exported template retains its existing framework configuration. A game explicitly requiring Vulkan is outside this build's compatibility range. The simulator library is not replaced: **build for an ARM64 iPhone, not the simulator**.

## Sign and install

For Xcode installation, first build the Godot 3 framework as described in [docs/godot3.md](docs/godot3.md) and add it to the target with **Embed & Sign**. Then select the `player` target, set a unique bundle identifier, enable automatic signing, choose your Apple development team and connected iPhone, then **Product → Run**. The dummy team in `bootstrap/export_presets.cfg` is only for unsigned project generation.

To distribute a signed IPA through Xcode, select a physical-device destination, **Product → Archive**, then **Distribute App** with the development/ad-hoc method available to your account. Provide the provisioning profile for that bundle identifier and device. Never commit signing keys or provisioning credentials.

Alternatively, sign `GodotPlayer-unsigned.ipa` with your existing personal sideloading tool and Apple identity, and install it using that tool. An unsigned IPA cannot be installed directly. The user has successfully done this for the preceding player build; this update has not yet been built or signed here.

## Additional iPhone regression tests

1. Build/install the player once. Copy `build/proof/movement.pck` and `counter.pck` into iCloud Drive or Files; neither is included as a playable bundled game.
2. Open the player, choose **Import Game**, and import Movement. Press Play. Verify the cyan animated circle, arrow controls, native touch button, and confirm button saving a move.
3. Close the process from the app switcher, reopen, launch Movement, and verify its saved count.
4. Close/reopen again. Import Counter into the **same installed application**, launch it, verify the orange animation and count/save button. No rebuild or reinstall is permitted between packs.
5. Repeat both games, confirming that their identical `user://proof.cfg` filenames retain independent values. Check UUID save folders and `player.log` under Files → Godot Player → GodotPlayerSaves.
6. Rename a game, replace its PCK using **Replace PCK (keep saves)**, and confirm saves remain. Delete only a disposable import, then try truncated/resource-only/encrypted packs and confirm useful errors.
7. Import the supplied reference game without changing its scripts, test its actual scenes/audio/touch, then exercise background/foreground, orientation, and a controller.

The user's two working imported games establish actual multi-game execution on the preceding build. The detailed regression scenarios above, along with mouse clicks/dragging, saved/remapped controls after reopening, and Pokémon startup, still need testing on the updated build. Passing desktop tests alone does not verify those changes.

For Windows desktop verification:

```powershell
python tools/desktop_proof.py "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --visible
python -m unittest discover -s tests -v
```

The desktop tool writes PCKs, logs and JSON evidence under `build/proof/`. It redirects Windows save storage into that directory. On macOS it uses the desktop engine's ordinary per-project save directories.

## Attribution

Godot's MIT license and upstream third-party notices are preserved in `licenses/`. Export preparation also embeds them in the app's existing localized resources. Source modifications retain upstream file headers. The original sample projects are MIT licensed under `samples/LICENSE`.
