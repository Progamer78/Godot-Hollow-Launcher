# Current limits and remaining work

The iOS runtime/launcher are source implementations awaiting Xcode compilation and physical-device validation. The next priority is a green CI archive followed by importing and running both test packs in one installed application. A successful standalone reference IPA does not establish this result.

The first adapter targets complete, unencrypted Godot 4 GDScript packs. Header metadata suggests a candidate runtime; it cannot prove rendering, bytecode, assets, API, autoload, or scene compatibility. A 4.7.2 runtime may fail older 4.x exports despite accepting their headers. Versions newer than 4.7 are rejected. Godot 3 is detected but cannot launch. The manual override selects among known adapters and never overrides an unsupported engine major.

The inspector supports pack-directory formats 1–4, separates the format version from engine version, validates bounded directory reads, paths, offsets, settings signatures and resource bounds, and rejects encrypted/sparse/delta/removal archives and obvious native/.NET dependencies. Asset payload checksums and dependency completeness are not exhaustively checked; a project may still be incomplete or fail to start. Encrypted scripts, external resource bundles, Windows native APIs, C#, GDNative and GDExtensions are unsupported. Native game-library loading is disabled at the engine boundary.

Metal and OpenGL ES are compiled. Explicit Vulkan-only settings, platform-specific textures, unsupported codecs, plugins, and desktop shader assumptions may require a compatible game export; there is no automatic asset conversion. The supplied reference is only desktop-initialized in this session; its complete iPhone gameplay remains a regression test to run against the player.

The official Godot controller/keyboard/touch paths are retained. New virtual buttons emit Godot key events with press/release semantics, arrow/WASD directions and limited editable extra keys. These controls, audio focus, rotation and safe areas are untested on iOS. Custom mouse-pointer overlays, arbitrary draggable layouts, gamepad-emulation buttons, scaling overrides, diagnostics toggles and FPS UI remain unimplemented. Touch-to-mouse behavior follows the selected game's Godot settings.

Per-game `user://` isolation is implemented for ordinary save APIs, including games with identical project names. It has not been device-tested. It is **not a security boundary between imported scripts**: ordinary GDScript can access other app-sandbox files by absolute path and can use network APIs when connectivity exists. iOS provides the app sandbox; this project does not implement a separate script sandbox. Import trusted games only. No online service is required to play.

There is one engine lifetime per process. After a launch attempt or engine setup failure, close and reopen the app. Returning to a running library, launching another engine in-process, crash recovery, and reliable engine teardown need further investigation. Logs created after Godot's file logger starts are in the UUID save directory; earlier initialization failures may only appear in the Xcode/device console.

## Godot 3 adapter plan

`PlayerRuntime` is the Objective-C runtime boundary and `RuntimeSelection` is the selection gate. Only the Godot 4 implementation is present. Godot 3.6.3 has not been linked, compiled, or executed in this app.

Adding 3.6.3 requires inspecting its older iOS bootstrap and GLES renderer and implementing the same pre-project pack selection and UUID save path. The standard 3/4 static archives cannot coexist directly: they export overlapping C++ names, C entry points, Objective-C classes and process-global engine state.

Investigate separately built, pre-signed bundled framework images, hidden/localized symbols and version-prefixed Objective-C classes/entry points, with a versioned adapter ABI. Mach-O two-level namespaces alone do not isolate Objective-C class registration or every global dependency. Both framework images must be built and signed with the IPA; no imported executable code is permitted. Loading/unloading or restarting either runtime must be proven before promising switching. If sufficient isolation cannot be demonstrated, source-level symbol/class namespacing and additional engine patches are compile blockers, not solved features.
