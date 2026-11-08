# Native Godot Player for iOS

The player has been built through GitHub Actions, installed on an iPhone, and used to run independently imported games. The user also reports the mouse/control update working, apart from its intrusive toolbar. **The new floating menu, Spine integration, and startup-failure handling require a new CI build and iPhone test.**

The launcher imports complete PCKs through Files and initializes the selected pack as Godot's **main project**. It does not mount games inside a Godot launcher project. The first adapter uses official Godot **4.7.2-stable**, revision `ed1daf0bf001b61586d9930840f2f1394092c079`.

Implemented source includes persistent UUID-based imports, directory validation, rename/delete, replacement while retaining saves, version metadata, runtime selection checks, renderer selection, editable key overlays, virtual mouse input, launch diagnostics, and a per-game `user://` path. Native rendering, audio, touch, keyboards, controller handling, and lifecycle continue through upstream Godot code.

Only one game can initialize per process. To choose another game, close the app from the iOS app switcher and reopen it. There is no subprocess, forced exit, simulated game execution, or assumed mobile restart API.

## Verified locally on Windows

- Official Godot 4.7.2 Windows executable checksum verified against release metadata.
- Two separate original projects exported to standalone PCKs and executed using `--main-pack` from an empty working directory.
- Both executed with headless rendering and with native OpenGL graphics windows; GDScript input, animation, autoload, and save/load checks passed.
- Each game loaded its previous saved value on another launch.
- Supplied `I Can Smell You From Here.pck` initialized headlessly, reported 97 dialogue nodes and successful game-data validation, then exited normally. Its gameplay was not tested.
- Python build-tool tests pass against the actual official release sources and an export-preparation fixture.

The earlier macOS GitHub Actions runs compiled the Swift pack inspector and passed all 253 original checks, including malformed/truncated files and the real sample packs. Both desktop PCK proofs also passed on macOS. After the export fixes, the user reports that two games work on the actual iPhone. Specific save-isolation, controller, and lifecycle scenarios still need separate device verification. The latest Swift tests add native-component warnings, old-manifest migration, saved controls, and compatibility gating; these additions run in CI and have not been executed from Windows.

The unmodified Pokémon Battle Advanced 0.3.3 PCK also reached its boot scene on Windows Godot 4.7.2 with no script/parse errors, using headless and graphical Compatibility runs. Its unavailable WebRTC backend and shutdown errors remain in the logs. This establishes desktop startup, not complete gameplay or iPhone compatibility.

See [test evidence](tests/results/validation.md), [reference inspection](docs/reference-inspection.md), and [remaining compatibility work](docs/compatibility.md).

## Build through GitHub Actions

1. Put these project files in a GitHub repository. Do not upload `GodotPlayerReference/`, `.cache/`, credentials, or generated `build/` files. The reference materials remain untouched locally.
2. Open **Actions → Build native Godot Player → Run workflow**. A push to `main` or `master` also runs it.
3. Leave **Bundled Spine version** at **4.2** for Goodbye Eternity 0.14.1. The workflow obtains matching official editor/templates, tests two packs, checks out immutable engine/Spine revisions, applies the source changes, and builds its ARM64 static library. The Spine runtime is compiled into the IPA, never loaded from imported games. The `none` option retains a standard build without Spine.
4. It uses the reference's existing `godot --export-release → xcodebuild archive → Payload ZIP` sequence. The custom runtime replaces only the exported ARM64 library. Exported framework links and Xcode source structure are preserved.
5. Download `GodotPlayer-build-and-tests`. A successful archive includes `GodotPlayer-unsigned.ipa`, both sample PCKs, and logs.

For the current update, extract `build/checkpoints/GodotPlayer-Floating-Menu-Spine-Update.zip` and upload its contents at the GitHub repository root using **Add file → Upload files**. Include the `.github`, `ios`, `tools`, `tests`, `docs`, and `licenses` folders, preserving their paths. The build executes `tools/patch_engine.py`, not a copy at the root. Commit the upload and run the workflow. The patch step should report `floating-menu-spine-v4`.

Sign the new IPA with the same app identifier and sideloading identity as the installed player, then install it as an update. Avoid uninstalling the existing app if you want to retain its library and saves.

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

For Xcode installation, select the `player` target, set a unique bundle identifier, enable automatic signing, choose your Apple development team and connected iPhone, then **Product → Run**. The dummy team in `bootstrap/export_presets.cfg` is only for unsigned project generation.

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
