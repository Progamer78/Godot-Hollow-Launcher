# Compatibility

Hollow bundles Godot 3.6.3 and Godot 4.7.2 in separately linked runtime images. A game is selected as the engine's main project, with a stable per-game save folder. Switching games requires closing and reopening the app.

Complete GDScript games are the main target. Header inspection checks paths, offsets, project settings and supported bytecode versions, but cannot prove every asset, script API, renderer or dependency will work. Older games can still depend on incompatible APIs or resources; games requiring a newer engine are refused.

PCK formats 1-4 are inspected. Patches, sparse packs, encrypted directories and incomplete projects need a complete supported export. ZIPs with several PCKs require selecting the intended complete pack outside the archive. Godot APK assets can be wrapped without changing their payload bytes; Android plugins and missing delivery/split assets cannot run on iOS.

Recognized Godot 3 Windows x64 runtimes can supply a key for ordinary GDEC encrypted scripts. Import the EXE and PCK together, or a ZIP containing both. Candidate keys must decrypt every encrypted script with matching plaintext checksums. ZIP recovery checks up to eight candidate EXEs of at most 128 MB each. It is not a universal decryption system and does not execute Windows code. The private key stays with the game's app storage and is excluded from portable layouts, support reports and save ZIPs.

.NET, Windows APIs, GDNative and executable GDExtensions from imported games are not loaded. Required native classes can prevent startup. The explicit Try without native extensions option is appropriate only when those components are optional. LimboAI is built into the Godot 4 runtime.

One Spine minor version is bundled per IPA. Match the game's animation data using the workflow's 4.1, 4.2 or 4.3 selection; these are not interchangeable. Source revisions and separate Spine notices are preserved.

Controllers use iOS GameController APIs. Independent extra buttons depend on controller mode, firmware and what iOS exposes. Remapped input uses the first connected controller and player-one gamepad output. Some paddles duplicate standard buttons and cannot be rebound independently.

Text save editing is limited to supported UTF-8 files up to 256 KB. JSON syntax checks do not guarantee a game accepts an edited value. Other text formats are preserved as entered. Binary/encrypted saves need game-specific decoding. Save backups preserve files written by the game, not its complete live process state.

The current native desktop tests pass in both engines. The new Apple model/UI tests, physical controller/gesture behavior, full iOS archive and this update's device regression checks still need execution. Historical real-game results are in tests/results/validation.md; successful decryption or import alone does not establish gameplay.
