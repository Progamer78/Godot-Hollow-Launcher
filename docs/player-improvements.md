# Player features and APK update

This is a combined source update, including the earlier Godot 3, joystick,
portrait, cosmetic, Lili/Spine/LimboAI, and all three framework link repairs.
The known export/archive pipeline remains in place. No game executable or
Android native library is executed or installed by the importer.

## Implemented

| Area | Behavior |
| --- | --- |
| Imports | Standalone PCK, a single PCK inside ZIP/APK, supported EXE footer-embedded PCK, and loose Godot APK `assets/` files. Assets are streamed into a standalone PCK without modifying their contents. Godot 3 paths retain the required `res://` prefix. APK exporter arguments and non-asset native libraries are excluded. |
| Compatibility | Existing encryption, .NET, native dependency and Godot 4 compiled-script checks remain. Godot 3 scripts newer than v13 are rejected before launch. Unsupported sparse/split APKs, ambiguous multi-pack archives, unsafe paths, duplicate entries, symlinks, CRC errors and oversized archives produce errors. |
| Update review | Before replacing a game, compare engine metadata, size, file count and native descriptors. A backup is created after confirmation. Game identity, saves and controls are retained; changing engine family resets incompatible runtime/renderer overrides. |
| Save protection | Manual backups; automatic backups before launch, game replacement, save import/restore and cheat editing. Retains five automatic backups and all manual backups until deletion. Backups exclude the engine log and rebuildable shader cache. Empty save directories are preserved. |
| Save tools | Staged restore with rollback, standard ZIP export/import, read-only preview of small UTF-8 JSON/CFG/INI/TXT/CSV saves. Restore/import are available from the library before launching the engine. Save ZIP imports refuse filename collisions on the device. |
| Recovery | Starting/running/backgrounded/failed launch journal; neutral interrupted-session notices; Safe Launch selects OpenGL, hides controls and applies 30 FPS for that session. It cannot decrypt scripts or supply missing classes. |
| Controls | Direct system keyboard over the game with a compact Esc/Tab/Paste/Done strip; committed text forwards immediately, including Unicode. Actual left/right analog gamepad axes, gamepad button/trigger mappings across both engines, fixed/floating positioning, held/toggled/repeating buttons and up to four additional chord keys. Modifiers are pressed first and released last. |
| Layouts | Platformer, WASD RPG, analog gamepad, visual novel and trackpad presets; bounded JSON import/export. High contrast borders, opacity and optional button haptics. Existing direct-touch/trackpad, click-drag, right-click, scroll and captured mouse behavior remain. |
| Input safety | Release All Inputs; cancellation on focus loss, layout changes and opening tools. Toggle state is visible. The optional monitor shows overlay-generated keys/axes and runtime FPS/scene information; it is not a trace of all hardware input. |
| Cheats | Per-game named pins resolved by current scene/resource label rather than persisted instance IDs; bounded numeric search and changed/unchanged/increased/decreased refinement; scene-object browser; live matching-value watches; up to twenty session freezes checked five times per second. Stale freezes are released; Undo clears freezes. |
| Performance | Saved game/default, 30, 60 and 120 FPS choices. Default restores the original game cap. Session engine time scale from 0.25x to 3x, with a warning about game logic/physics and unchanged audio speed. |
| Display | Existing portrait fit and landscape support; per-game safe-area margin. Native mouse coordinate conversion follows the actual game view. |
| Library | Search, favorites, collection labels, notes, most recently played ordering and foreground play time. Earlier colors and floating-menu design are preserved. |
| Storage/support | Game/save/backup sizes, clearing only the known shader cache, compact filtered support reports with app paths redacted and no save/PCK/full-log attachment. Bundled component information is shown locally. Review reports before sharing. |
| Build checks | Native archive regression tests, Swift save/import/model tests and actual APK-derived sample execution configured before ARM64 compilation. Final IPA checks require ARM64 app/framework images, notices, correct image kinds and no accidental bundled game pack. Existing symbol/Objective-C collision audits remain. Artifacts retained for 90 days subject to repository limits. |

## Import and save limits

APK support extracts Godot data; it does not emulate Android. Android Java/native
plugins, unsupported texture formats, external asset-delivery/OBB data, encrypted
exports and custom engine components can still prevent execution. Exact original
engine versions cannot always be recovered from loose assets. The generated pack
records the inferred major family with minor/patch zero and displays that fact;
use the library's APK engine hint if detection is ambiguous. ZIPs containing more
than one PCK currently require selecting/extracting the desired pack outside the
app. EXEs must have the supported PCK footer; old absolute-offset embeds may be
rejected rather than silently rewritten.

Archives are limited to 200,000 entries, 32 MB of path metadata, 16 GB per entry
and 32 GB total uncompressed data. Extraction uses bounded buffers and validates
CRC. Save operations are limited to 100,000 entries, 4 GB per file and 8 GB total.
Save preview is limited to 256 KB. Large operations can take time and require
free space for staging plus backups. Backups preserve file-based saves, not a
running engine's memory. Games saving on background threads can still write
during a copy; use the game's save function before making important backups.

Pins depend on stable scene/resource labels and are never automatically applied
at startup. Value search covers at most 150 numeric results within the existing
600-object/12,000-value scan, rather than arbitrary process memory. Freezing is
periodic and cannot guarantee invincibility or bypass game-specific validation.
Missing or ambiguous pinned variables are refused. Live edits persist only when
the game saves them.

## Deliberately deferred

- Physical controller interception/remapping to arbitrary keyboard/mouse inputs:
  Godot 3's GameController and Godot 4's SDL paths need separate handling to avoid
  delivering both original and remapped events. Native controller support remains.
- Adaptive rendering resolution, display zoom/panning and custom touch calibration:
  these require renderer and coordinate regression testing on actual devices.
- Automated compatibility recipe distribution, additional downloadable native
  modules, universal encrypted-game support, save-format conversion and raw memory
  scanning. Required executable components must be built into a signed IPA.
- Custom cover artwork, extra themes, two simultaneous virtual sticks and advanced
  multi-finger mouse gestures. Native library organization and existing mouse
  interaction remain available.

## Verification

- Both complete Windows runtimes compile with the current shared module.
- **66 actual native checks pass in each engine (132 total)**, including nested
  edits/undo, 64-bit values, numeric refinement, freezes, frame caps/default
  restoration, time scale, analog/button state/release, scene browsing and full
  Unicode text events received by a real scene.
- **16 Python/native archive/package-helper tests pass** locally. Archive tests
  execute compiled C++ with the bundled MiniZip/zlib, including stored/deflated
  ZIP64, byte-preserving extraction, unsafe/duplicate/symlink rejection, CRC
  failure cleanup and save ZIP/empty-directory round trips. IPA tests use a
  structural fixture, not a real newly built IPA.
- Native extraction plus an independent Python implementation of the chosen APK
  pack layout runs the original sample games in stock Godot 3 and 4, with their
  input/animation/save proof markers. This proves the layout and extraction,
  **not the uncompiled Swift packer**. Actions additionally compiles the actual
  Objective-C/Swift importer and runs its resulting Godot 4 PCK.
- Captive Lili's unchanged PCK still passes a 180-frame headless startup in the
  updated desktop runtime, without script or bytecode-version errors. Full
  gameplay, rendering and saves on an iPhone are not established by that test.
- Fifteen Swift files pass a local syntax parser; YAML/Python parse. **No new
  Swift type-check, complete iOS framework/launcher build, signed IPA or device
  test has run here.** Those require macOS Actions and an actual device. The new
  save/import/Swift model cases are configured there but remain unexecuted here.

## Build and device checks

Extract `GodotPlayer-Features-APK-Update.zip` and upload every included folder at
the existing GitHub repository root, preserving `.github`, `bootstrap`, `ios`,
`runtime3`, `runtime_shared`, `tools`, `tests`, `samples` and `docs`. Run **Build
native Godot Player**, Spine **4.2**. Download/sign the unsigned IPA and its
embedded framework, then install over the existing app with the same identity
and app identifier. Do not uninstall if you want to retain the library and saves.

On device, first check a previously working Godot 4 game, then Godot 3 in a fresh
process. Test text entry, analog strength, chords/toggle/repeat and focus release.
Use a disposable save to verify backup/restore/ZIP transfers and cheat undo/freezes.
Import a simple full APK and compare its behavior with the original standalone
PCK. Check large imports/storage pressure and renderer-specific textures. These
are required acceptance checks, not results claimed by this update.
