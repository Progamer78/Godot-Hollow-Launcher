# Native Godot Player for iOS

This is an initial native player implementation, with real desktop PCK proofs. **The new iOS code has not been compiled or run on an iPhone yet. No new IPA has been produced.** The supplied reference IPA is an existing standalone game, not validation of this player.

The launcher imports complete PCKs through Files and initializes the selected pack as Godot's **main project**. It does not mount games inside a Godot launcher project. The first adapter uses official Godot **4.7.2-stable**, revision `ed1daf0bf001b61586d9930840f2f1394092c079`.

Implemented source includes persistent UUID-based imports, directory validation, rename/delete, replacement while retaining saves, version metadata, runtime selection checks, renderer selection, key overlays, launch diagnostics, and a per-game `user://` path. Native rendering, audio, touch, keyboards, controller handling, and lifecycle continue through upstream Godot code. Device behavior still needs verification.

Only one game can initialize per process. To choose another game, close the app from the iOS app switcher and reopen it. There is no subprocess, forced exit, simulated game execution, or assumed mobile restart API.

## Verified locally on Windows

- Official Godot 4.7.2 Windows executable checksum verified against release metadata.
- Two separate original projects exported to standalone PCKs and executed using `--main-pack` from an empty working directory.
- Both executed with headless rendering and with native OpenGL graphics windows; GDScript input, animation, autoload, and save/load checks passed.
- Each game loaded its previous saved value on another launch.
- Supplied `I Can Smell You From Here.pck` initialized headlessly, reported 97 dialogue nodes and successful game-data validation, then exited normally. Its gameplay was not tested.
- Python build-tool tests pass against the actual official release sources and an export-preparation fixture.

Swift pack-inspector tests are provided for macOS CI, including malformed/truncated files and the real sample packs. They have **not** been executed locally. Desktop save persistence does **not** verify the new iOS save-isolation patch.

See [test evidence](tests/results/validation.md), [reference inspection](docs/reference-inspection.md), and [remaining compatibility work](docs/compatibility.md).

## Build through GitHub Actions

1. Put these project files in a GitHub repository. Do not upload `GodotPlayerReference/`, `.cache/`, credentials, or generated `build/` files. The reference materials remain untouched locally.
2. Open **Actions → Build native Godot Player → Run workflow**. A push to `main` or `master` also runs it.
3. The workflow obtains matching official editor/templates, tests two packs, checks out the immutable engine revision, applies the narrow source changes, and builds its ARM64 static library.
4. It uses the reference's existing `godot --export-release → xcodebuild archive → Payload ZIP` sequence. The custom runtime replaces only the exported ARM64 library. Exported framework links and Xcode source structure are preserved.
5. Download `GodotPlayer-build-and-tests`. A successful archive should include `GodotPlayer-unsigned.ipa`, both sample PCKs, and logs. **This workflow has been authored, not run in this session.**

The engine rebuild is necessary: official release templates default to disabling external main-pack overrides, initialize before a game can be selected, and share one Documents save path. It is an application-runtime build, performed once per player version, not once per imported game.

## Build manually on macOS

Use Xcode with the iOS SDK and Python 3. Install the **4.7.2 standard editor and official export templates**. Put the editor's executable on PATH as `godot`, then run from this repository:

```sh
mkdir -p .cache build/ios
git clone https://github.com/godotengine/godot.git .cache/godot-source
git -C .cache/godot-source checkout ed1daf0bf001b61586d9930840f2f1394092c079
python3 tools/desktop_proof.py "$(command -v godot)"
swiftc -swift-version 5 ios/PCKInspector.swift tests/pck/main.swift -o build/pck-tests
build/pck-tests build/proof/movement.pck build/proof/counter.pck
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
python3 tools/prepare_xcode.py build/ios .cache/godot-source/bin/libgodot.ios.template_release.arm64.a
open build/ios/player.xcodeproj
```

The generated Xcode project is the reproducible project configuration. `bootstrap/` exists only to obtain the official export; its pack is emptied during preparation and is never a fallback game. Reapply patches to a **clean** engine checkout after source changes; the patcher rejects repeated application.

The initial custom build contains Metal and OpenGL ES. Vulkan is disabled to avoid rebuilding MoltenVK; the exported template retains its existing framework configuration. A game explicitly requiring Vulkan is outside this build's compatibility range. The simulator library is not replaced: **build for an ARM64 iPhone, not the simulator**.

## Sign and install

For Xcode installation, select the `player` target, set a unique bundle identifier, enable automatic signing, choose your Apple development team and connected iPhone, then **Product → Run**. The dummy team in `bootstrap/export_presets.cfg` is only for unsigned project generation.

To distribute a signed IPA through Xcode, select a physical-device destination, **Product → Archive**, then **Distribute App** with the development/ad-hoc method available to your account. Provide the provisioning profile for that bundle identifier and device. Never commit signing keys or provisioning credentials.

Alternatively, sign `GodotPlayer-unsigned.ipa` with your existing personal sideloading tool and Apple identity, and install it using that tool. An unsigned IPA cannot be installed directly. This session did not perform signing or installation.

## Critical iPhone acceptance test (still pending)

1. Build/install the player once. Copy `build/proof/movement.pck` and `counter.pck` into iCloud Drive or Files; neither is included as a playable bundled game.
2. Open the player, choose **Import Game**, and import Movement. Press Play. Verify the cyan animated circle, arrow controls, native touch button, and confirm button saving a move.
3. Close the process from the app switcher, reopen, launch Movement, and verify its saved count.
4. Close/reopen again. Import Counter into the **same installed application**, launch it, verify the orange animation and count/save button. No rebuild or reinstall is permitted between packs.
5. Repeat both games, confirming that their identical `user://proof.cfg` filenames retain independent values. Check UUID save folders and `player.log` under Files → Godot Player → GodotPlayerSaves.
6. Rename a game, replace its PCK using **Replace PCK (keep saves)**, and confirm saves remain. Delete only a disposable import, then try truncated/resource-only/encrypted packs and confirm useful errors.
7. Import the supplied reference game without changing its scripts, test its actual scenes/audio/touch, then exercise background/foreground, orientation, and a controller.

Passing the desktop tests alone does not meet this acceptance test.

For Windows desktop verification:

```powershell
python tools/desktop_proof.py "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --visible
python -m unittest discover -s tests -v
```

The desktop tool writes PCKs, logs and JSON evidence under `build/proof/`. It redirects Windows save storage into that directory. On macOS it uses the desktop engine's ordinary per-project save directories.

## Attribution

Godot's MIT license and upstream third-party notices are preserved in `licenses/`. Export preparation also embeds them in the app's existing localized resources. Source modifications retain upstream file headers. The original sample projects are MIT licensed under `samples/LICENSE`.
