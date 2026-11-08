# Validation recorded November 7, 2026

## Godot 3 navigation archive repair - November 8

The latest supplied Actions run passes 263 PCK checks, model tests, nine Python tests and complete iPhone Swift type-checking, then compiles the Godot 3 ARM64 library including its native-plugin callbacks. Linking now fails on 75 duplicate Recast symbols. The upstream navigation SCsub appends `thirdparty_obj` after collecting Recast, adds RVO2 to that same list, then appends the entire accumulated list again. Eleven Recast object members enter the archive twice; ten contain the 75 strong duplicate symbols. `force_load` reveals the otherwise dormant archive issue. The supplied official Godot 3.6.3 iOS release template also contains precisely these 75 duplicates, confirmed by LLVM's Mach-O symbol inspection; no other strong duplicate symbols were found in that reference archive.

The engine patch now accumulates all enabled Recast/RVO2 objects and appends them once. It retains every unique source and the complete module dependency list for all four enable/disable combinations. Navigation stays enabled. Existing force-load, hidden-symbol, namespace/export and Objective-C collision checks remain unchanged. No duplicate-definition suppression or dynamic symbol lookup was added to the application build.

Ten local tests pass without skips. New regression coverage executes the actual original and patched SCsub, reproducing the eleven duplicated objects and checking all four configurations. The ARM64 native fixture now also force-loads real archives, failing with repeated members and succeeding with each member once. An additional local proof extracts the eleven actual Recast ARM64 objects from the official template: all paired copies are byte-identical; duplicated copies fail an LLVM Darwin force-load link and a single list passes. That isolated reference-object check uses `dynamic_lookup` solely because the Apple math/libc/C++ SDK dependencies are unavailable locally; it is not a runnable framework or the app's link policy. The reference archive was not modified. Local evidence is under `build/navigation-archive-proof/` and summarized in `godot3-navigation-link-fix.json`.

The complete repaired framework link and its post-link audits, Godot 4 ARM64 compilation, IPA archive/packaging/signing and device tests remain pending in Actions. No new IPA was produced here or by the failed run.

## Godot 3 exported plugin callback repair - November 8

The next supplied Actions run passed 263 PCK checks, model tests, eight Python tests and complete iPhone Swift type-checking, then compiled the Godot 3 ARM64 archive. Its framework link reported two undefined C++ symbols: `godot_ios_plugins_initialize()` and `godot_ios_plugins_deinitialize()`. Upstream `platform/iphone/api/api.cpp` calls them; `platform/iphone/export/export.cpp` normally generates their definitions in the exported Xcode project. A separately linked engine framework cannot use that project's generated definitions. It now compiles `runtime3/player3_plugins.cpp` through the patched iPhone SCsub, supplying the same empty callback bodies used for an empty exported-plugin list. Built-in modules retain normal registration. Imported native plugins remain disabled. The prior AudioToolbox link repair is retained. AudioUnit/CoreAudioTypes/UIUtilities autolink warnings in the log were not the fatal diagnostic; no private framework is added.

Nine local tests pass without skips. The new native regression compiles the actual upstream iOS API and callback source as ARM64 iOS Mach-O objects using LLVM. Linking the API alone reproduces both missing symbols; linking it with the callback object succeeds and `llvm-nm --undefined-only` reports no unresolved symbols. This is a real focused ARM64 link, not a mocked linker or a full engine/framework/device test. The suite also checks that the iOS patch stages and compiles this exact source. On macOS Actions, that regression uses the selected iPhone SDK and Apple's compiler/linker before the engine build. Full framework linking, Godot 4 ARM64 compilation, packaging/signing and device execution remain pending; no new IPA has been produced.

## Godot 3 framework link repair - November 8

The latest supplied Actions logs passed all 263 Swift PCK checks, the persisted-model/control/compatibility checks, seven Python tests and type-checking of the complete iPhone Swift launcher. Both Godot 3 ARM64 adapter and full static archive compiled. The next command failed linking `Godot3Runtime.framework`: `ld: framework 'AudioUnit' not found`. This is a link-helper error: iOS exposes Audio Unit headers but links those functions through AudioToolbox, as described in Apple's [Audio Unit Extensions presentation](https://devstreaming-cdn.apple.com/videos/wwdc/2015/508691kyzp/508/508_audio_unit_extensions.pdf).

Removed the separate AudioUnit framework flag, retaining AudioToolbox and the existing engine isolation/export settings. Eight Python tests pass locally. The new fixture exercises command generation, device SDK selection, force-loading, sole bridge exports, Objective-C metadata audit, notice packaging and rejection of leaked engine symbols. Its linker is mocked; it does not establish a successful iOS framework link. The repair still needs Actions compilation, Godot 4 ARM64 build, final archive/IPA packaging and device tests. No IPA was produced by the failed run or locally.

## Compatibility and game tools update - November 8

The user's supplied Coffee/Lili failures are from the preceding working player, not the untried Godot 3/joystick/portrait update. The new combined package includes both sets of changes.

Captive Lili reproduced an access violation in stock 4.7.2 after rejecting its 500 v100 compiled scripts. Legacy header/token translation and pinned built-in LimboAI 1.8.1 now allow its unchanged PCK to execute for 180 frames headlessly and 180 frames with native OpenGL in the compiled 4.7.2 desktop runtime: exit 0, no script errors or bytecode rejection. The graphics window was positioned offscreen; visual correctness/full gameplay were not assessed. Certificate-store and shutdown resource/texture leak messages remain.

Coffee's 96 GDEC-encrypted scripts all match their PCK directory MD5 values. A normal startup attempt in compiled Godot 3.6.3 + Spine 4.2 with the standard engine key produces decryption failures and 72 error messages, including required autoload failures. Exit code 0 does NOT mean the game ran. It remains unplayable without a suitable unencrypted export/matching-key runtime; native dependencies may require further work. No key extraction or PCK rewriting was performed. Import errors now explain the encryption blocker and count.

Both complete Windows release engines compiled with the shared PlayerTools module, and **48 native checks pass in each (96 total)** using original standalone test PCKs. They verify real live scalar/nested edits, 64-bit values/IDs/keys, type/stale-object/overflow/non-finite guards, undo, pause restoration, expressions and the JSON transport used by the app. Compiled module bytes match the current workspace source. The custom Godot 3 engine also starts the original Sadiubus PCK with exit 0 and no script errors.

Seven Python tests pass against real upstream patch anchors and staging/export fixtures. YAML and embedded Python parse successfully. New Swift inspector/model/tool-transport cases are configured in Actions but have not run locally. **The new iOS adapters/UI/framework have not compiled/run here and no new IPA was produced.** See `compatibility-cheats.json` and `docs/game-tools.md` for exact evidence, limitations and build/device steps.

Earlier results follow.


## Godot 3 / joystick / portrait update ? November 8

The user reports the preceding Godot 4/Spine/floating-menu player working on iPhone. This update adds the isolated Godot 3 framework/bridge, fixed and floating keyboard sticks, saved orientation preferences and portrait aspect fitting. It preserves the original game PCKs and the existing Godot 4 export/archive process.

The supplied official ARM64 static archives were inspected with LLVM's Mach-O tools. They share 18,264 defined external symbols. The new design separates engine images, prefixes 17 Godot 3 Objective-C class/protocol names, and exports only a versioned bridge; the real exported-symbol/Objective-C metadata audits run at CI link/package time.

Actual Windows execution: official, checksum-verified Godot 3.6.3 started the unchanged Sadiubus PCK (3.4.2 metadata, format 1, 1,927 entries) with exit 0 and no script errors. `samples/godot3` was exported to a standalone PCK and run twice from an empty directory for 90 frames per launch; input, movement and save reload passed (loaded counts 0 then 1). Those runs use the official desktop engine, not the new iOS adapter.

Six Python tests pass, covering the real 3.6.3/4.7.2 patch anchors, export preservation, Spine staging/version guards and the framework collision-check fixture. YAML and embedded Python parse successfully. New Swift migration/joystick/portrait/runtime-selection tests and complete iOS launcher type-checking are configured in Actions. Swift is unavailable locally, so those new Swift cases have not run.

**No new ARM64 framework, iOS launcher or IPA has compiled/been produced here.** Windows has no Xcode/iOS SDK. Native integration, code signing and actual Godot 3 execution in the same installed IPA as Godot 4 remain pending. Joystick multitouch/release behavior, portrait click coordinates, audio focus and save persistence need device testing. See `godot3-joystick-portrait.json` for concise evidence and `docs/godot3.md` for the implementation and acceptance steps.

The following sections describe earlier validation history.


## Spine build repair

The latest supplied GitHub Actions logs passed all 256 PCK inspector checks, the control-profile migration/persistence/save-preservation tests, and iPhone Swift type-checking. Compilation stopped in the new Spine module on missing `callable_mp` and `RS` declarations, followed by cascading `SpineMesh2D` errors.

A portable LLVM-MinGW compiler was downloaded into the workspace cache and verified against the official release SHA256. Actual compilation against the pinned Godot 4.7.2 sources then exposed additional API changes: rendering enum/type namespaces, animation-library `LocalVector` iteration, missing floating-point/scene-tree headers, and reference-counted JSON/format-loader allocation. The staging tool now adapts these in its copied module; it preserves upstream source files and the Spine 4.2 data version. JSON uses scoped references, and loader/saver references are explicitly released at module shutdown.

The corrected module compiled and archived successfully for Windows x86_64, template_release: **100 object files**, zero compiler errors. A fresh run of the staging tool produced files identical to the compiled module (228 source/header/config/license files checked). Four Python tests pass with regression checks for the adaptation and unchanged source checkout. Logs, commands and the compiled archive are local under `build/spine-compile-proof/`; concise results are in `spine-build-fix.json`.

The complete Godot 4.7.2 Windows release template also built successfully (546 seconds). It then executed the unchanged Mac Goodbye Eternity PCK for 90 headless frames: exit 0, zero script errors, zero missing-Spine-class errors, and the splash scene loaded. A temporary adjacent-PCK NTFS hard link was used because this desktop build retains the release default disabling CLI path overrides; the iOS workflow independently enables external `--main-pack`. No game files were modified. Certificate-store and shutdown object/resource leak messages remain; visual rendering, input and full gameplay were not tested. This establishes real C++ compilation and startup against Godot 4.7.2, rather than only source generation or the earlier 4.6.1 desktop test. The full iOS archive and device execution remain pending. The floating controls/menu source is unchanged by this repair.

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
