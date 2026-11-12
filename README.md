# Godot Hollow Launcher

A native, offline iPhone launcher for Godot games you supply. Import games after installation and play with the bundled Godot 3.6.3 and 4.7.2 engines.

- PCK, ZIP, Godot APK and embedded-PCK EXE imports.
- Automatic encrypted-script key recovery for recognized Godot 3 Windows x64 exports, including ZIPs containing the matching EXE and PCK.
- A searchable library with favorites, collections and sorting.
- Saved touch layouts, up to four virtual joysticks, controller rebinding and controller-stick mouse control.
- Trackpad gestures, second-finger left/right click, portrait fitting and an optional performance HUD.
- Per-game saves, backups, ZIP transfers and protected editing of small text saves.
- Live variable-name searches, numeric/boolean value filtering and a selectable pinned-value monitor.

## Getting started

1. Tap **Import** and choose your game in Files. For an encrypted Godot 3 game, choose its original EXE and PCK together or import a ZIP containing both. Keep Hollow open while large files are prepared.
2. Open the game page and tap **Play Game**. Saves and settings belong to that game's library identity.
3. Tap the small in-game **...** button for controls, keyboard, mouse, gestures and game tools. Drag that button if it covers the game.
4. To switch games, close Hollow from the iOS app switcher and reopen it. One game can start per app process.

Open the library's gear button for **Settings & Help**. The performance HUD is off by default; choose any corner. It shows engine FPS, average frame interval, process/physics time and available engine allocation memory. It does not intercept touch input.

In **Game Tools > Pins**, select **Show in monitor** on up to five pins. Selecting a pin enables the monitor; the overall toggle can hide it. Use **Rename** for a short custom label. Names and values have separate lines in the monitor. Use **Edit** to drag pins into order, or hold a pin and choose **Move to Top**. Order and selection save per game, and the monitor follows that order without blocking taps. Frozen variables show a snowflake/Frozen indicator; Pins also lists active freezes with individual Unfreeze buttons.

**Search** combines name/path, type, value and change filters. Candidates, baseline, filters and page survive closing tools during the running game. Refreshing values and switching pages preserve the comparison baseline; only narrowing advances it. **Scene** shows active paths, script names, connected signals and snapshot changes. See [search and scene tools](docs/search-scene.md).

For click-while-moving, open **Touch Gestures > Second-finger click** and select Left or Right. This enables trackpad mouse mode. Hold/move one finger and tap another free area to click at the current pointer, without moving it. This takes priority over other multi-finger gestures.

## Progress and save editing

Open a game page, then **Saves, Backups & Transfers**. Restore and import ask before replacing progress and create a backup first. Export saves before deleting a game or removing the app.

Small UTF-8 JSON, CFG, INI, TXT and CSV saves can be edited before Play. JSON can be formatted for readability, and its syntax is checked before saving. Edits create a backup and reject stale files. Variable names and supported values depend on the game. Binary/encrypted saves are not decoded. These are save-file backups, not emulator-style exact-frame save states.

## Build and install

1. Open your repository on GitHub, select **Actions > Build native Godot Player > Run workflow** and choose the branch containing this update.
2. Keep Spine **4.2** for games with 4.2 assets. Choose 4.3 for games that require 4.3. One Spine version is bundled per build.
3. Download **GodotPlayer-build-and-tests** after a successful run. It contains **GodotPlayer-unsigned.ipa**.
4. Sign the application and its embedded **Godot3Runtime.framework** with your signing tool, then install. Keep the same app identity when updating to preserve your library and saves.

The working official iOS export/Xcode pipeline is retained. The launcher and Swift module target iOS 15 or later. The display name is Godot Hollow Launcher; existing storage paths and bundle identifier are preserved.

**Reuse engine compiler outputs** is enabled by default. The first build fills the cache; later builds can reuse unchanged engine objects. Disable it for a clean diagnostic build. In the observed final UI update, the whole job took 5m 38s with cache reuse versus 12m 31s for the cold build; engine build stages fell from 8m 1s to 49s combined. Actual time depends on the runner and cache availability. A new branch/compiler/SDK/Spine variant may need a cold build.

## Compatibility and verification

A valid import is a compatibility candidate, not a guarantee of gameplay. Required native plugins, .NET, unsupported encryption, missing resources and engine/Spine version differences can prevent a game from running. See [compatibility](docs/compatibility.md).

For this update, both Windows engine builds compiled and each executed **94 native checks (188 total)**, including performance metrics, boolean/name filtering and direct pinned-value reads. **25 Python/native helper tests pass**, and 27 Swift source/test files pass syntax parsing and a narrow local-declaration scan. The SVG icon was rendered by Godot at 1024 pixels with an opaque background.

**GitHub Actions has passed 270 pack-inspector checks, the expanded Swift models, the complete iPhone type-check, the archive importer link check and actual UIKit input tests in an iPhone simulator.** Both iPhone engines compiled, the Xcode archive succeeded, and the unsigned IPA passed its ARM64/framework/packaging audit. [Final Actions build](https://github.com/Progamer78/Godot-Hollow-Launcher/actions/runs/43149671399). Physical second-finger input and new UI/controller behavior need device testing. Earlier iPhone success reports apply to earlier builds. See [this update's verification and device checks](docs/hollow-release.md) and [recorded results](tests/results/validation.md).

Hollow is independent of the Godot Foundation. Godot and third-party notices are preserved and available in Settings & Help. Imported scripts share the app's sandbox; only import games you trust.

## Contributing

This project is **entirely vibe coded**..

Feel free to submit pull requests, fix things, add features, improve compatibility, or just fork the whole thing and do whatever you want with it. You have pretty much free rein.

I mainly made this because I wanted to play Godot games on my iPhone.

## Credits

Built using [Godot Engine](https://godotengine.org/). Godot and its dependencies retain their respective licenses. Spine support is subject to its [separate license](https://github.com/EsotericSoftware/spine-runtimes/blob/4.2/LICENSE).
