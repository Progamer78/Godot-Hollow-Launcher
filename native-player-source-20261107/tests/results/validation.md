# Validation recorded November 7, 2026

Environment: Windows, Python 3.12, official Godot `4.7.2.stable.official.ed1daf0bf`. Editor download SHA256:

`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`

This matches the official release asset metadata. The actual engine sources were downloaded and the narrow patch anchors were tested against that release.

| Check | Actual result |
| --- | --- |
| Original Movement PCK exported | Passed, 9,396 bytes |
| Original independent Counter PCK exported | Passed, 8,180 bytes |
| Movement main-pack execution from empty directory | Passed twice, saved counts loaded as 3 then 4 on final run |
| Counter main-pack execution from empty directory | Passed twice, saved counts loaded as 3 then 4 on final run |
| Movement autoload initialization | `movement-autoload`, assertion passed |
| Injected key events, movement/animation, save operations | Both games reported their PASS markers |
| Native graphics execution | Both passed with OpenGL 3.3 Compatibility on Intel Arc 130V; loaded 5, saved 6 |
| Supplied reference game | Headless startup exited 0 after 90 frames; 97 dialogue nodes and validation OK |
| Python build tools | 2 tests passed: real-source patch anchors and export-preparation fixture |
| Python syntax compilation | Passed for tools and tests |
| Swift inspector compilation/tests | Not run; macOS CI configured |
| SwiftUI / Objective-C++ / custom Godot ARM64 compilation | Not run; no connected macOS/Xcode environment |
| Player iOS save isolation, import, controls, audio, lifecycle | Not tested on device |
| Same installed IPA launches two imported packs | Not tested; central acceptance test remains pending |
| New unsigned or signed IPA | Not produced |
| Godot 3 execution | Not implemented/tested |

The initial restricted run could not access the Windows certificate store. Successful desktop runs used approved normal Windows access and redirected APPDATA into the workspace. There were no script/engine errors in the final proof logs.

Full import/export/runtime logs and packs are local under `build/proof/`; selected concise logs and JSON results are copied alongside this report. Reproduce using the commands in the root README. Counts increase on subsequent proof runs, so the runner checks persistence relative to the prior count instead of hardcoding zero.

Desktop saves use Godot's existing per-project desktop paths. They establish ordinary GDScript save/load behavior, not the correctness of the new UUID save override on iOS. The reference PCK test establishes initialization only, not full gameplay compatibility.
