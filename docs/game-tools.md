# Game tools and compatibility update

The failures supplied for this update came from the preceding Godot 4/Spine player, not from the untried Godot 3/joystick/portrait update. This package includes both updates so only one upload is needed.

## Captive Lili

The original PCK identifies Godot 4.4.1 and contains 500 compiled scripts using tokenizer version 100. Stock Godot 4.7.2 rejects them and reproduced the supplied crash on Windows (access violation). Version 101 added an ellipsis token and removed a header field. The runtime now reads the [older header/token format](https://github.com/godotengine/godot/blob/4.4.1-stable/modules/gdscript/gdscript_tokenizer_buffer.cpp) and translates token IDs in memory; it does not edit or re-export the game. It still accepts its normal v101 format. Bounds/count checks were added before tokenizer allocations and reads. The pack inspector records script versions and rejects unknown formats before launching.

Lili also includes a LimboAI descriptor. [Official LimboAI 1.8.1](https://github.com/limbonaut/limboai/tree/e45e60e976dafab7f2c15cc341ae366e4cf3352b) is now compiled into Godot 4, with its MIT notice preserved. Its descriptor is satisfied by that built-in module; imported DLLs/dylibs remain disabled. Other native components retain their existing compatibility checks.

The complete Windows Godot 4.7.2 runtime compiled with these fixes, Spine, LimboAI and PlayerTools. The unchanged Lili PCK then ran for **180 frames headlessly and 180 frames using native OpenGL**, both exit 0, no script errors and no bytecode-version failures. The OpenGL window was positioned offscreen; visual correctness and full gameplay were not assessed. Certificate-store and shutdown resource/texture leak messages remain. This does not verify iPhone rendering, gameplay or saves.

## Anomalous Coffee Machine

This PCK has Godot 3.6.0 metadata and **96 encrypted `.gde` scripts**, including required autoloads/main-game code. Every encrypted file's MD5 matches its PCK directory entry. A locally compiled Godot 3.6.3 runtime with Spine 4.2 was used to attempt normal startup with the standard engine key. It reported decryption/checksum failures and could not load the game scripts. Its process exit code was 0 despite 72 error messages; that is **not a successful game launch**.

The import error now describes the actual encryption blocker and script count instead of blaming the first Steam example. Adding Godot 3 or changing renderer does not supply the game's encryption key. The current player cannot run this encrypted copy. An unencrypted export or an appropriately supported matching-key runtime is needed; Steam/native dependencies may require further compatibility work after that.

Its scene resources also use SpineSprite/SpineSkeletonDataResource and Spine 4.2.43 animation data. The official Spine module's existing Godot 3 branch is now staged and compiled into the Godot 3 runtime as well, without applying Godot 4-only API changes. That complete Windows engine compiles, starts the unchanged Sadiubus PCK without script errors, and passes the tools tests below. Actual Coffee animation/gameplay execution remains blocked by encryption. No keys were extracted or game payloads rewritten.

## Cheats and expression console

While playing, choose **⋯ → Game Tools · Cheats & Console**.

1. Search for a variable name: money, gold, coins, health, hp, stamina or level. Quick searches and **All** are available.
2. Tap a result, enter its new value, then **Apply**. Integers, decimals, booleans and short strings are editable, including values inside dictionaries, arrays and script resources. Paths show which game object owns the value.
3. **Undo Last Edit** tracks up to 20 edits for that process. It refuses to overwrite a value the game has changed since the edit. Freed objects, missing entries, type changes, overflow and invalid values produce errors instead of writing to an old address.
4. **Pause game while editing** defaults on. Closing tools restores the game's previous pause state. Existing mouse/joystick/button input is released when opening tools.
5. **Console** evaluates Godot Expressions against the scene root. For example, if an autoload is named `Game`, `get_node('Game').get('money')` reads a property and `get_node('Game').set('money', 9999)` changes it. Use the game's actual names. This is an expression console, not the editor's remote debugger or a full multiline GDScript REPL. Console changes are not tracked by Undo.

Edits affect live game state. They persist when the game saves; the player does not guess or invoke an unknown save function. It does not rewrite the PCK or automatically freeze stats. Some games keep stats in unsupported/native/custom containers, static variables, computed getters, or scene branches outside the bounded scan. Discovery is limited to 600 objects, 12,000 values, 150 results and five levels of nested data, with bounded array/dictionary reads. Search prioritizes matching variable names. Required encryption and game-specific logic are not bypassed.

The same portable `runtime_shared/player_tools` C++ module runs in both engines. Only JSON crosses the adapter boundary, using text for full-width object IDs and integer values. It resolves IDs before access, validates types/paths, reads script properties on the main thread and verifies writes. Session history is owned by the scene root rather than by a global destructor. The Godot 3 bridge is now ABI version 2.

## What was actually verified

- Both complete Windows release runtimes compiled: 4.7.2 + Spine/LimboAI/PlayerTools, and 3.6.3 + Spine/PlayerTools.
- **48 actual native tools checks passed in each runtime** (96 total), using independently exported original PCKs. Checks cover live scalar/nested edits, resource IDs, 64-bit integer values/keys, undo, pause restoration, expressions, malformed/non-finite values, freed/type-changed objects and the JSON transport used by the app. Commands and logs are in `build/tools-proof/` and `build/coffee-lili-proof/` locally.
- Seven Python build-helper tests pass against actual upstream source anchors and fixtures. New Swift inspector/model cases cover v100/v101 headers, unsupported future formats, detailed encryption errors, optional metadata migration, LimboAI gating and tools JSON round trips. Those new Swift cases have not run locally because Swift/Xcode are unavailable on Windows.
- **The new iOS UI, Objective-C adapters and framework have not compiled/run here; no new IPA was produced.** Actions performs Swift tests/type-checking, ARM64 compilation, framework export/Objective-C collision audits, license embedding and the existing unsigned IPA archive/package flow. Both engines in the same installed IPA still need device testing.

Extract `GodotPlayer-Compatibility-Cheats-Update.zip`, upload all included folders/files at the existing repository root, including **runtime3**, **runtime_shared**, **bootstrap** and **.github**, then run **Build native Godot Player**, Spine **4.2**. Sign the app and embedded framework with the same identity/app identifier and install as an update. Avoid uninstalling if you want to retain saves. Requires iOS 15+. Test a previously working game, Lili, tools/undo and the Godot 3 proof; close/reopen the process between games. Coffee will continue to show the encryption error for this copy.
