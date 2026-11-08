# Validation recorded November 7, 2026

## Simulator display-frame timing repair - November 8

The newest simulator run passed the shared lifetime audit, 100 real control construction/removal cycles, idle joystick checks, direct Unicode/Backspace/paste and global input release. It then failed because no cursor display-link callback had arrived during a fixed 0.8-second interval. The assertion tested simulator frame delivery rather than cursor update correctness; no game-runtime crash or app compile failure is shown by this log.

The cursor updater is now shared by the actual display-link callback, initial mouse-view attachment and the simulator test. Initial attachment takes a synchronous cursor snapshot before scheduling display callbacks. The test directly runs that updater, checking revision/position/visibility reads and the resulting visible UIImageView position. It no longer depends on a rendered frame arriving within a fixed time. Real display-frame scheduling is explicitly outside this test's scope. Each major test phase now prints a progress marker.

All 21 local Python/native helper tests pass without skips, and all 20 Swift files parse locally. The supplied Apple simulator execution establishes that the preceding input checks run successfully; the corrected cursor test, final app build and game/device regression checks still need macOS execution. No new IPA was produced locally.

## Simulator lifetime audit false-positive repair - November 8

The latest supplied logs passed full iPhone Swift type-checking and the standalone optimized iPhone archive bridge link. The input smoke app compiled, installed and launched in the iPhone simulator. Its first assertion incorrectly rejected the compiler-generated dealloc on KeyButton, which has a legitimate Swift deinit. Simulator shutdown then timed out and replaced the original failure with a cleanup traceback. This was a test error; it does not establish a new game crash.

The shared runtime audit permits generated dealloc while retaining checks for release/retain/autorelease/retainCount. The separate source audit still rejects hand-written Objective-C lifetime callbacks. A new macOS Foundation-only test exercises the exact same audit before booting the simulator: a real Swift NSObject subclass with deinit must pass and deallocate normally, while runtime metadata defining a release callback must fail. Simulator cleanup now attempts both shutdown and delete and cannot replace a successful result or hide the original exception. The app's crash and keyboard fixes are preserved.

All 21 Python/native helper tests pass locally without skips, including timeout/error cleanup regressions. All 20 Swift source/test files parse locally. The corrected native macOS and simulator tests, final app archive and device behavior remain pending on macOS/Actions. No new IPA was produced locally.

## Controls lifetime, mouse startup and direct keyboard repair - November 8

The user reports the previous IPA launches in safe mode but crashes on showing controls, with another failure using an already-enabled mouse. Errors/player.log has no native crash backtrace. It records successful game initialization and a separate Spine 4.3.08-versus-4.2 asset mismatch, followed by texture conversion warnings. The exact native exception therefore remains unverified.

Source review found the new notification callback `@objc func release()` on KeyButton. Earlier working buttons had a Swift-only method with that name. Exporting it replaces NSObject's release selector, interfering with UIKit/ARC lifetime operations. The callback and all call sites now use resetHeldInputs. Actual input views moved into InputViews.swift so they can run independently in a simulator test. A callback audit rejects reserved lifetime selectors, including explicit Objective-C name aliases. Mouse views and native cursor/input calls now wait for main-project startup; mouse touches cancel on focus loss and global input release. Joystick refreshes preserve active holds unless size/configuration changes, and idle gamepad sticks do not create virtual controllers just to emit zero axes.

KeyboardInput.swift replaces the large modal editor with the ordinary iOS keyboard over the unchanged game viewport and a 40-point Esc/Tab/Paste/Done accessory strip. Committed text forwards immediately, marked IME text is buffered until commit, Backspace reaches the game even with an empty hidden responder, and Unicode paste requests are bounded without splitting scalars. No saved game files or stored control layouts are changed by these fixes.

All 19 Python/native helper tests pass without skips locally; 18 Swift source/test files parse without syntax errors. The audit reproduces the forbidden old callback and verifies current callbacks. Actions now builds a small disposable iPhone simulator app using the actual InputViews/KeyboardInput/GameInput sources and recorded engine endpoints. It checks runtime selector metadata, 100 control construction/removal cycles, cursor polling, direct Unicode input, Backspace, bounded paste and input cleanup before either engine build. That simulator test and new iPhone Swift type-check remain unexecuted on this Windows host. This does not claim verified device crash resolution or new IPA production. For the game in player.log, the existing workflow's Spine 4.3 choice is needed for its 4.3 assets; that is separate from the common control failure. One compiled Spine version cannot promise compatibility with assets from other Spine versions.

## Archive importer C++ link repair - November 8

The latest supplied run passed 266 PCK checks, the complete Swift model/archive/save tests, actual Swift APK packing followed by execution of the resulting PCK (input, animation and saves), all 16 prior helper tests and full iPhone Swift type-checking. Both full ARM64 engine archives compiled. The Godot 3 framework linked successfully and passed symbol/Objective-C audits. Xcode's final app link then failed on `std::__1::__allocator_destroy<allocator<PlayerArchive::Entry>, Entry*, Entry*>`, referenced by vector growth in ArchiveSupport.o.

The archive bridge now includes the public memory header explicitly and compiles in its own cloned SCons environment with modules disabled, avoiding dependence on the engine's C++ module imports for this template definition. Other engine drivers and Swift retain their module flags. The missing body is inferred to involve the modular header/instantiation path; that compiler-level cause cannot be reproduced with Apple's SDK on this Windows host. No private libc++ definitions, duplicate-symbol suppression or unresolved-symbol allowances were added.

An early Actions step compiles the actual staged bridge plus bundled MiniZip sources for arm64 iPhone at size optimization with exceptions disabled, then links them against Foundation/zlib/libc++ with undefined symbols treated as errors. It runs before both engine builds and uploads its result metadata. The native desktop archive helper now uses the same optimization, exception and module settings. Seventeen local Python/native tests pass, including the actual patched SCsub source graph (bridge once, scoped flags), preflight command validation and real archive/CRC/path round trips. The preflight itself, repaired final app link and IPA packaging await macOS execution. No new IPA was produced locally.

## Features, save vault and APK update - November 8

Both complete Windows engines compile with the current shared module, and 66 actual native checks pass in each (132 total). New checks cover numeric refinement, periodic freezes, original frame-cap restoration, engine time scale, analog/controller button state and release, scene browsing and full Unicode text events delivered to a real scene. Both compiled module source trees match the workspace. Sixteen Python/native archive/build/package-helper tests pass without skips. Native archive tests compile and execute the bundled MiniZip/zlib code, including indexed entry identity, ZIP64, CRC cleanup, unsafe paths/duplicates/symlinks, and save ZIP/empty-directory round trips. The package audit uses a structural IPA fixture, not a newly built IPA.

Native indexed extraction plus an independent Python implementation of the loose-APK pack layout executes the original Godot 3 and 4 sample games, including their input/animation/save proof markers. The Godot 3 reference reader's required res:// path prefix is preserved. This is architectural/extraction proof; the actual Swift packer remains unexecuted locally and is tested in the updated macOS workflow. Captive Lili's unchanged pack still passes a 180-frame headless startup in the updated desktop runtime, with no script/bytecode errors; full gameplay/device execution remains unverified.

Fifteen Swift source/test files pass syntax parsing. YAML and Python parse successfully. New save-vault, transfer, retention, symlink, oldest-snapshot restoration, APK, embedded pack and layout-model cases are configured for macOS with the real Objective-C archive bridge. **They have not run locally. No new Swift type-check, Apple bridge/framework/launcher build, signed IPA or device test was performed here.** Windows has no Apple SDK. The workflow preserves the export/archive path, includes all earlier framework fixes, and adds APK execution/package audits. See `player-improvements.json` and `docs/player-improvements.md` for current hashes, feature limits and deferred work.

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
## Joystick default persistence repair - November 8

The latest supplied Actions run compiled the PCK inspector and passed 266 checks. It also compiled the native macOS archive bridge and the Swift models/importer/save-vault test executable. Execution stopped at the first persisted-layout assertion: joystick normalization changed an absent optional axis into explicit axis 0. The original layout and reopened layout therefore differed even though both select the left stick. This is an actual settings-normalization bug, not an Xcode/linker failure.

Normalization now preserves absent and valid explicit axes (0 and 2); invalid explicit axes still fall back to 0. The existing full-library persistence assertion is retained, with additional checks for optional/explicit axes, JSON persistence, invalid-axis repair and repeated normalization. The 16 Python/native helper tests pass locally without skips. Swift source syntax checks pass locally; the updated Swift regression executable cannot be run on this Windows host. Archive/save/import tests after the failing assertion, full iPhone Swift type-checking, engine linking and IPA packaging remain unverified for this revision. No new IPA was produced here.

## Save-folder ancestor alias repair - November 8

The newest Actions logs passed all 266 PCK checks and the joystick/layout migration and persistence assertions. The compiled macOS model executable then stopped at the first save-backup assertion (expected only the save JSON bytes). SafeFiles checked canonical containment but calculated relative names against the unresolved original root. When Foundation expands an ancestor alias such as /var to /private/var in enumeration URLs, that prefix mismatch corrupts relative names, cache exclusions and destination paths.

SafeFiles now enumerates the resolved root and derives names from the same resolved prefix used for containment. It still rejects a save root that is itself a symbolic link and links within the save tree. The Swift regression additionally creates an explicit ancestor alias, checks exact file/directory names, cache/log exclusions, copied bytes and backup byte counts. Those updated Swift tests await execution on macOS; local parsing of all 15 Swift files passes, and all 16 Python/native helper tests pass. The latest failed run confirms the original model executable and archive bridge compiled; it does not verify the remaining save/APK tests or complete iPhone type-check/build/link/package stages. No IPA was produced locally.

