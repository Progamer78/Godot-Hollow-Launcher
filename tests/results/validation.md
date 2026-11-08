# Validation recorded November 7, 2026

## Floating menu and Spine update

The user reports the preceding mouse/control update working on iPhone apart from the permanent toolbar. This update replaces it with a 44-point, translucent, movable menu handle, initially collapsed. The settings panel exists only when opened, and toggle changes close it. Gesture handlers attach before positioning so they do not acquire an invisible screen-sized drag region. Opening the panel does not resize the rendering view or saved-control canvas. UI compilation and touch behavior of this change remain untested on iPhone.

Both supplied Goodbye Eternity logs identify Compatibility rendering and missing `SpineSprite`, `SpineAnimation`, `SpineAnimationState`, `SpineTrackEntry`, `SpineSkeleton` and `SpineSkeletonDataResource`, followed by a failed splash scene. The two logs have identical contents. They do not establish a Metal-versus-OpenGL difference or a size-related memory failure.

Inspection read only the archive directory and small skeleton prefixes, without extracting the whole game. Windows: embedded format-3 pack, Godot 4.6.1, 7,329 entries, 2,194,788,562 pack bytes. Mac: standalone format-3 PCK, Godot 4.6.1, 2,194,788,719 bytes. Both contain Spine 4.2 skeletons; samples include 4.2.38, 4.2.39, 4.2.40 and 4.2.43. Neither contains a native library/extension descriptor.

| Current check | Actual result |
| --- | --- |
| Standard Godot 4.7.2 + unchanged Windows embedded pack | Exit 1; 22 script errors, 16 missing-Spine-type errors, main scene failed; reproduces iPhone failure |
| Official Spine 4.2-enabled Godot 4.6.1 + same embedded pack | Headless startup, 90 frames, exit 0, zero script errors, no main-scene failure |
| Same Spine-enabled desktop engine + original Mac standalone PCK | Headless startup, 90 frames, exit 0, zero script errors, no main-scene failure |
| Actual selected Spine source staging | Pinned revision verified; 100 C++ source files staged into engine modules; normal Godot registration/include layout and exact license preserved |
| Python tests | 4 passed: source patching/start-result guards, export preparation/Spine notice, module staging/version guards, no-Spine build |
| Workflow | Parsed YAML and embedded Python; default Spine 4.2, immutable version-specific source commits, optional no-Spine build, artifact license included |
| Startup failure handling | Source captures actual Main::start result rather than assuming a created main-loop object means success; fixture guards passed; native alert not device-tested |
| New iOS compilation/IPA | Not performed/produced from Windows |
| New floating-menu touch behavior / Goodbye Eternity iPhone gameplay | Not tested |

The desktop Spine-enabled runs still logged restricted Windows certificate-store access and shutdown resource leaks. These tests establish startup/resource/script compatibility in that official 4.6.1 desktop engine; they do not establish full gameplay, graphics output, device memory use, or compilation of the new 4.7.2 iOS module. The Windows game EXE was read as a pack container, not executed. Mac assets and original game files were not modified.

The official Spine source is 4.2 revision `5cb78e77d3711ddcd80c7bd043bb11cf70fcc88c`. The desktop test engine came from the official Spine download linked by its runtime documentation; URL/checksum and concise structured results are in `eternity-startup.json`. Full logs are local in `build/eternity-proof/`, excluded from source ZIPs. Native import loading remains disabled; Spine is a trusted, statically compiled dependency in the IPA. Its separate license is embedded by export preparation and included in the build artifact.

The evidence below records the earlier implementation and tests; pending mouse/editor entries refer to their status before the user's latest device report.

The user reports successfully building and installing the preceding player and running two independently imported games on an actual iPhone. The supplied `Errors/(Smell)player.log` and `Errors/(Physician)player.log` confirm custom Godot 4.7.2 ARM64 execution on A17 Pro, using Compatibility and Mobile renderers respectively. This is real multi-game player evidence. It is user-reported device testing, not an automated device test performed here.

## Current mouse/control update

| Check | Actual result |
| --- | --- |
| Existing user library migration | Optional manifest fields preserve existing game IDs/settings; new Swift migration/persistence tests added, awaiting CI |
| Saved control editor | Source implemented: drag, key/label/size changes, add/delete/reset, draft cancel, atomic per-game save; awaiting iOS compilation/device testing |
| Mouse support | Source implemented: Apple display-server APIs, cursor image/state, Retina coordinate conversion, relative/direct movement, clicks/dragging/double-clicks/wheel, capture mode; awaiting iOS compilation/device testing |
| Named virtual key codes | All named picker keys checked against the pinned official keyboard table; Control maps to Ctrl |
| Source integration | Python tests pass against clean official 4.7.2 source fixtures, including mouse header/features and copied Swift sources |
| Export preparation | Python fixture test passes; preserves existing export and archive pipeline |
| Python syntax | Tools/tests compile successfully |
| Workflow | YAML parsed; new pack/model tests and early iPhone Swift type-check are configured |
| Updated Swift inspector/model tests | Added fixtures for optional native components, old library migration, persisted remappings/layouts, save preservation, portrait defaults and runtime gating; not executed on Windows |
| New iOS runtime / IPA | Not compiled or produced in this Windows session; requires GitHub Actions/macOS |
| Updated mouse/editor on iPhone | Not tested |
| Godot 3 | Selection boundary retained; runtime not implemented, compiled or tested |

The device logs explain the missing mouse: upstream iOS reports `mouse_get_position` unsupported, warns on `mouse_set_mode`, and rejects custom cursors. The update implements those APIs and adds an explicit toolbar toggle instead of relying on game touch-to-mouse settings.

## Pok?mon Battle Advanced investigation

The original import error rejects `addons/webrtc_native/webrtc_native.gdextension`. The recovered project descriptor has no iOS library, and its networking scripts construct the WebRTC backend when host/join is used. Inspection of the original complete PCK found format 4, Godot 4.7.1 metadata, 11,860 entries, 120,091,308 bytes, and one native descriptor; Windows DLLs were not embedded in this PCK.

The unchanged original pack was started from an empty working directory with official Godot 4.7.2 on Windows:

- Headless startup: exit 0 after 180 frames; no `SCRIPT ERROR` or `Parse Error`.
- Graphical startup: Compatibility renderer, exit 0 after 240 frames; the original `scenes/front/boot.tscn` completed loading; no `SCRIPT ERROR` or `Parse Error`.
- Native WebRTC was unavailable. Shutdown reported object/resource leaks and node-path errors; a restricted certificate-store error also occurred. These were not clean full-gameplay runs.

Full local evidence is in `build/pokemon-proof/`; concise results accompany this report. This proves desktop startup without that extension, not full gameplay or iPhone compatibility. No scripts or pack contents were modified. The importer now records native components as warnings; Play requires explicit ?Try without native extensions.? Actual native loading remains blocked. WebRTC multiplayer is unsupported.

## Earlier verified foundations

| Check | Actual result |
| --- | --- |
| Official Windows engine | Godot `4.7.2.stable.official.ed1daf0bf`; release checksum verified |
| Movement and independent Counter packs | Both exported and executed headlessly and in OpenGL windows using `--main-pack` from an empty directory |
| Sample input/animation/autoload/save/load | Both emitted PASS markers and loaded saved counts across subsequent launches |
| Supplied Smell pack desktop startup | Exit 0, 97 dialogue nodes and game-data validation OK; later user reports actual iPhone gameplay working |
| Previous Swift inspector tests | Earlier macOS CI compiled and passed all 253 original checks |
| Previous macOS sample proofs | Both passed headlessly, twice, with saved counts restored |
| Previous custom ARM64 engine/launcher | Third CI run passed iOS Swift type-check and full SCons compilation |
| Xcode export fixes | Missing ETC2/ASTC setting and icon reproduced and fixed; official-template export/prepare verified locally; subsequent user installation and game execution establish a successful player build |
| Detailed iPhone save isolation/lifecycle/controller scenarios | Still need specific regression tests; ordinary successful gameplay alone does not establish every scenario |

Official Windows executable SHA256: `731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`.

Original proof logs/JSON are preserved beside this file and under `build/proof/`. Export reproduction results are in `ios-export-results.json` and `build/ios-export-proof/`. Earlier CI failures were a missing renderer controller header, an incorrectly uploaded root patcher rather than `tools/patch_engine.py`, then bootstrap export configuration. The working build pipeline and those fixes are retained.
