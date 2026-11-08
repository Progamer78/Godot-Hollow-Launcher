# PROJECT: Godot Player for iOS

## Role and objective

You are an expert software engineer specializing in Godot Engine internals, C++, Objective-C++, Swift, SwiftUI, iOS application development, and game engine portability.

Your task is to build a real, native, offline Godot game player for iOS, distributed as a single IPA application.

The app must allow users to import independently obtained Godot `.pck` game files and run them directly on their iPhones using the original Godot engine.

This is not a game converter, streaming application, remote desktop client, or Windows emulator.

The objective is to reproduce the functionality of an ordinary Godot game exported to iOS, except that users can select which game's PCK to run after the player has already been installed.

The long-term goal is support for Godot 3.x and 4.x within the same application, with high compatibility, good performance, and minimal user intervention.

**Priority: Produce a genuinely functional game player, not merely a game-library interface or simulated demonstration.**

## 1. Development constraints

- My development environment is Windows with VS Code.
- The target device is a modern ARM64 iPhone.
- The target application is a sideloadable iOS IPA.
- The game player must operate completely offline after installation.
- No game streaming, remote servers, or Windows emulation.
- Import `.pck` files directly through the iOS Files application.
- The player must not require users to manually edit, convert, or re-export each game.
- Do not reconstruct or independently implement the Godot engine.
- Reuse official Godot engine source, export templates, and platform functionality wherever possible.
- Preserve the native engine's original graphics, scripting, physics, audio, and scene systems.
- Avoid unnecessary dependencies, complex abstractions, and premature optimization.

Avoid repeatedly reading large portions of the Godot source tree or placing unnecessary source files into the language model context.

Use targeted searches, source inspection, testing, and minimal patches.


## 1.5. Existing working iOS export reference

The directory `GodotPlayerReference/` contains materials from a Godot game that I have already successfully exported to iOS, built into an IPA using GitHub Actions, installed, and launched on my iPhone.

Before changing the build system or engine bootstrap, inspect this reference.

Determine:

1. Which Godot engine version and official iOS template were used. Answer: Godot 4.7 Stable
2. How the original PCK is packaged and selected at startup.
3. Which project settings, export options, and build modifications were necessary.
4. Whether the existing GitHub Actions workflow can be reused.
5. What minimum changes would permit selecting a different imported PCK before engine initialization.

Preserve the known-working pipeline where possible.

Use the existing game as a regression test, but do not hardcode the player to that game.

The critical test is launching a second, independently produced compatible PCK without rebuilding the IPA.

Do not confuse a successfully exported standalone game with a functioning multi-game player.

Avoid unnecessary modifications to working code and build configurations.

## 2. Official engines and licensing

Use the official Godot repository:

https://github.com/godotengine/godot

Initial engine version:

Godot 4.7.2-stable

Planned secondary runtime:

Godot 3.6.3-stable

Use these verified releases as starting points rather than arbitrary development branches. Check whether a later stable patch release is available before pinning dependencies.

Godot is MIT licensed. Preserve its copyright notices, license, and applicable third-party attribution.

Relevant documentation:

https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html

https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_ios.html

https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html

https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html

Do not blindly copy the existing export template. Inspect how its application entry point, engine initialization, project settings, resource paths, and iOS lifecycle work.

Determine the smallest safe modification that allows the runtime to select an external PCK before initializing the game project.

## 3. Required application behavior

The final intended user experience is:

1. Install one Godot Player IPA.
2. Open the application.
3. Select "Import Game."
4. Choose a `.pck` file through the iOS Files picker.
5. The application copies the PCK into its private storage.
6. The application examines the PCK and identifies its Godot version when possible.
7. The imported game appears in a persistent game library.
8. Select the game and press Play.
9. The application selects an appropriate bundled Godot runtime.
10. The original game starts natively with its scenes, scripts, graphics, audio, and gameplay.
11. The user plays using touchscreen controls or a connected controller.
12. Saves persist between application launches.
13. Other imported games remain available independently.

The user should never need to run a separate computer, manually patch the game, or install another IPA for every new game.

## 4. Architecture requirements

Prefer this architecture:

- Native Swift/SwiftUI launcher and game library.
- PCK inspection and metadata manager.
- iOS filesystem and save management.
- Engine-selection abstraction.
- Native Godot runtime adapters.
- Objective-C++/C++ bridge between the launcher and engines.
- Native input translation.
- Configurable compatibility profiles.

However, do not assume that Godot can be embedded and restarted as an ordinary library.

Before implementing the full architecture, investigate the actual iOS lifecycle and demonstrate a minimal integration.

The official Godot export template should be the starting point.

A separately selected game must initialize as the main Godot project, not simply as an additional resource pack inside an unrelated launcher project.

Investigate the existing `--main-pack` startup mechanism and the relevant project setup code.

For iOS, determine how to supply the selected PCK path before engine initialization.

Make the smallest practical modifications to the official initialization flow.

Do not rely solely on `ProjectSettings.load_resource_pack()` to simulate launching independent projects. That function can mount resources but does not guarantee correct project initialization, autoloads, settings, or isolation.

Do not assume `OS.set_restart_on_exit()` works on iOS. It does not support automatic mobile restart.

If clean engine teardown and reinitialization cannot be implemented reliably within the initial attempts, prioritize correct cold-start execution and document the temporary limitation.

Avoid unsupported subprocess execution or dynamically installing unsigned executable code.

## 5. Initial implementation: Godot 4

Prioritize a fully functional Godot 4 player before implementing Godot 3.

The initial runtime should use Godot 4.7.2 or a newer verified compatible stable patch version.

It should:

- Run native ARM64 code.
- Use an officially supported iOS graphics backend.
- Load compatible complete Godot 4 PCKs.
- Initialize project settings from the selected game.
- Execute the game's original GDScript.
- Load the original scenes, resources, and autoloads.
- Support ordinary audio and rendering.
- Preserve original gameplay logic.
- Handle standard game input.
- Provide persistent saves.

Do not claim that every Godot 4 game will work.

A newer engine may not correctly run every older release, particularly when exported script formats, renderer requirements, or engine APIs differ.

Initially use the latest compatible stable 4.x engine. Add additional runtime versions only when testing demonstrates they are needed.

Do not silently change the contents of imported games.

## 6. PCK import and validation

Implement importing through the native iOS document picker.

Store imported packs in an application-controlled games directory.

Required features:

- Import standalone `.pck` files.
- Copy imported files safely into persistent app storage.
- Display imported games in a library.
- Keep unique identities for games.
- Preserve game files across application launches.
- Allow a game to be renamed in the library without modifying its PCK.
- Allow users to delete games.
- Prevent path traversal, malformed file access, and unexpected writes outside intended directories.
- Avoid loading the entire PCK into memory simply to inspect its header.
- Validate basic archive structure before launch.

Implement PCK header inspection using the appropriate official Godot pack-format specification.

Read version metadata where available.

Distinguish the engine version stored in the PCK from the pack-format version.

Do not assume header information establishes perfect runtime compatibility.

Support manual engine-version override in case detection is ambiguous or incorrect.

An imported file may be a patch, resource-only archive, encrypted archive, incomplete game, or game requiring external files.

Detect these cases when possible and produce meaningful errors.

Do not fake successful imports when the game is not actually runnable.

## 7. Native iOS UI

Create a clean, functional interface rather than spending excessive time on visual design.

Required screens:

**Game Library**
- List of imported games.
- Import button.
- Play button.
- Rename and delete functionality.
- Game metadata when available.

**Game Details**
- Detected Godot version.
- Selected runtime.
- File size.
- Launch settings.
- Compatibility status and errors.

**Settings**
- Controller layout options.
- Touch-control visibility.
- Aspect-ratio/scaling preferences where feasible.
- Runtime override.
- Diagnostic logging.

Use standard iOS system components where practical.

Prioritize performance, stability, and accessibility over complex animations.

Do not spend a significant portion of the token budget generating decorative interfaces before real game execution works.

## 8. Input and controls

The player should support games originally designed for keyboard, mouse, touchscreen, or gamepad input as far as possible.

Implement:

- Native touch input passed to Godot.
- Virtual directional pad.
- Confirm and cancel buttons.
- Customizable additional buttons.
- Keyboard key emulation.
- Optional mouse click and pointer controls.
- Bluetooth game controller support through iOS-supported APIs.
- Configurable control layouts per game.
- Ability to show or hide virtual controls.

Common mappings should include:

Arrow keys, WASD, Enter, Escape, Space, Shift, Control, Tab, and common gamepad buttons.

Use the native Godot input system and proper input events.

Do not emulate input by editing each game's GDScript.

Where possible, allow custom mappings for games using nonstandard input actions.

Handle screen orientation, resolution scaling, and iPhone safe areas.

Do not assume all games are controllable with one fixed virtual D-pad.

## 9. Saves and storage

Each imported game should have persistent, independent save storage.

Use a stable internal game identifier.

Prevent unrelated games with identical project names or save filenames from overwriting one another.

Investigate how Godot resolves `user://` on iOS and implement proper per-game isolation where necessary.

Retain normal Godot save APIs so existing games do not need modification.

Do not unnecessarily change save serialization.

Test that saves persist after closing and reopening the app.

Support different game sizes without keeping all assets in memory.

Preserve data when a game is updated or reimported unless the user explicitly chooses deletion.

## 10. Godot 3 support

Godot 3 support is a core long-term objective, but it must not jeopardize the initial Godot 4 implementation.

Use the official Godot 3.6.3 iOS runtime as the starting point.

The intended final application should contain both Godot 3 and 4 support.

Investigate:

- Differences in engine initialization.
- Differences in iOS rendering.
- Differences in PCK formats.
- Linker symbol collisions.
- Engine-global and singleton state.
- Static versus dynamic framework integration.
- iOS code signing.
- Engine shutdown and isolation.
- Per-version input bridges.

Do not simply link the two standard Godot static libraries into one executable and assume they will coexist.

Determine whether they can be packaged as separately isolated, pre-signed native components and selected safely at runtime.

If this requires significant engine refactoring, document the exact architecture and compile blockers.

Do not claim multi-version support until both runtimes have launched actual test games inside the same installed iOS application.

If Godot 3 integration cannot fit within the available budget, leave a well-defined adapter interface and complete the functional Godot 4 implementation first.

## 11. Compatibility strategy

The player should prioritize compatibility with independently distributed Godot games.

Use generalized engine-level compatibility fixes, not individual game rewrites.

Possible compatibility features include:

- Alternate graphics renderer selection when supported.
- Touch/keyboard mappings.
- Display-scaling adjustments.
- Correct resource path handling.
- Save-directory isolation.
- Version-specific engine selection.
- Better error reporting for missing resources.
- Game-specific settings profiles.

Recognize unavoidable limitations.

Windows-only GDExtensions, GDNative libraries, C# dependencies, native Windows APIs, incompatible compressed textures, missing files, and encryption may prevent games from running.

Do not pretend these problems can always be fixed automatically.

Do not attempt to download unsigned native code or bypass iOS code-signing requirements.

Prioritize ordinary GDScript games with complete PCKs and iOS-compatible resources.

If a Windows-exported PCK relies on unsupported platform-specific assets, report the exact issue.

## 12. Performance requirements

This application must execute games natively on the iPhone.

Do not add an unnecessary rendering layer or software emulator.

Use Godot's existing optimized rendering, scripting, audio, and physics implementations.

Avoid decompressing or duplicating entire games unnecessarily.

Minimize idle CPU usage in the launcher.

Respect iOS application lifecycle events.

Provide frame-rate and diagnostic logging if feasible.

Do not promise full-speed operation for every game without measurements.

## 13. Security and platform restrictions

Imported PCKs may contain untrusted GDScript.

Treat imported files as untrusted.

Keep filesystem access within the application's sandbox.

Ensure per-game storage separation where feasible.

Avoid automatically requesting unnecessary iOS permissions.

Do not silently download additional game executables.

Do not implement native library loading from untrusted imported PCKs.

Support personal sideloading initially.

App Store distribution is not a required first milestone.

Preserve all applicable open-source licenses and copyright notices.

## 14. Build environment and IPA generation

Official iOS compilation requires macOS and Xcode.

Implement as much as possible locally, including file inspection, project structure, desktop runtime testing, and source changes.

Create a reproducible Xcode build configuration.

If a suitable macOS build environment is connected, use it to compile and test the iOS app.

Otherwise, provide an appropriate macOS CI workflow and instructions for compiling the application through Xcode.

Do not embed signing certificates or credentials in source control.

Document how the user can sign and install the IPA.

If an actual IPA cannot be built because no macOS build environment or signing credentials are available, report that explicitly.

Do not claim that the app was successfully built or installed unless that was verified.

## 15. Mandatory validation tests

Create a minimal original Godot test project with GDScript.

Export it as a standalone PCK.

The game should display a visible scene, accept input, perform a simple animation or movement, and demonstrate save/load functionality.

Test the pack using the matching desktop Godot engine and its main-pack startup mechanism.

Then test native iOS execution.

Critical acceptance test:

A compatible game must launch from an imported PCK after the iOS application has already been built.

Changing the selected game must not require rebuilding the IPA or modifying that game's scripts.

Create a second independent test game to establish that game selection is genuine and not hardcoded.

When Godot 3 integration is available, add a Godot 3 test PCK.

Maintain a clear distinction between:

- Source code generated.
- Successfully compiled code.
- Tests completed on desktop.
- Tests completed on iOS.
- Signed IPA produced.
- Real third-party games actually tested.

Never report success based solely on code generation.

## 16. Development order

Follow this order carefully.

**Milestone A: Technical foundation**

Inspect official Godot iOS startup and export code.

Identify how an external main PCK can be selected before engine initialization.

Determine a realistic integration strategy.

Document blockers briefly, then continue with feasible implementation.

**Milestone B: Standalone PCK proof**

Build or obtain a properly licensed sample project.

Export its PCK and demonstrate real execution through the official Godot runtime.

**Milestone C: iOS runtime proof**

Create the smallest possible iOS build using the official Godot template.

Demonstrate initialization from a selected external PCK.

Do not create an elaborate UI before this milestone is established.

**Milestone D: Minimum functional player**

Add persistent imports, game library, launch selection, and basic controls.

**Milestone E: Robustness**

Add save isolation, errors, lifecycle handling, additional input options, and a second test game.

**Milestone F: Multi-version support**

Investigate and implement Godot 3 integration using separate runtime adapters where feasible.

The first five milestones take priority over the sixth if the token budget becomes restrictive.

## 17. Deliverables

Produce a real project containing:

- Native iOS application source.
- Required Godot integration changes.
- PCK inspection code.
- Import and game-library implementation.
- Runtime selection architecture.
- Touch input implementation.
- Reproducible Xcode build configuration.
- macOS CI build configuration where appropriate.
- Original sample game project and export instructions.
- Tests and their results.
- Build and signing documentation.
- A compatibility limitations document.
- A concise report of remaining work.

Use standard project layouts and keep unrelated generated files out of version control.

Do not create placeholder systems that pretend to execute games.

Do not claim that Godot 3 support exists when only an adapter interface has been written.

## 18. Working instructions

Work autonomously through the development milestones without repeatedly requesting approval for ordinary engineering decisions.

At the beginning, perform a focused technical inspection of the relevant official Godot source and documentation.

Then begin implementing the actual runtime proof immediately.

Use Git commits or another reliable checkpoint system to preserve working progress.

Prefer small, buildable changes.

Run tests whenever the available environment supports them.

If an iOS-only issue cannot be tested from Windows, document it and continue with independently verifiable implementation work.

Avoid repeated broad searches of the Godot source tree.

Avoid unnecessary source rewrites.

Prioritize existing APIs and upstream functionality.

Do not spend significant effort on graphical polish until runtime execution has been proven.

If an approach fails, explain the technical blocker and choose the least disruptive documented alternative.

Preserve the original objective of a single IPA supporting imported PCKs. Do not quietly replace it with individual per-game exports.

Stop before the spending ceiling if it can be reliably measured.

At the end, report:

1. What was actually implemented.
2. What successfully compiled.
3. Which game PCKs were actually executed.
4. Whether an iOS IPA was produced.
5. What remains for Godot 3 support.
6. Which compatibility limitations remain.
7. Exact instructions for building, signing, installing, and testing the current result.

**Above all, prioritize getting one original Godot game running natively from an independently imported PCK. That is the central technical milestone.**