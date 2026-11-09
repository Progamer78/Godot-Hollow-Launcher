# EXE imports, controller bindings and touch controls

Import Game now accepts selecting an original EXE and its separate PCK together.
For recognized Godot 3 Windows x64 exports, the app inspects the EXE as data,
finds candidate script keys and validates every encrypted script before adding
the game. It does not execute Windows code or rewrite the PCK. The validated
key is stored in that game's private app folder and passed to the isolated
Godot 3 runtime before project initialization. Existing games remain separate.
An EXE containing an embedded PCK can still be imported alone.

This supports the ordinary GDEC script-encryption format, not arbitrary DRM,
encrypted Godot 4 pack directories, obfuscated runtimes or missing native
libraries. EXE inspection is capped at 128 MB, with up to 32 candidates and
16 MB per encrypted script. A mismatched or unsupported pair is refused.
Keys are excluded from library/layout JSON, save ZIPs and support reports.

Open Controller Bindings & Stick Mouse in game details, or Controller Bindings
in the in-game menu. Enable the profile and assign buttons to keyboard keys,
mouse buttons or canonical Pad inputs. A live status line identifies pressed
buttons, including extra buttons reported independently by iOS. Controller
profiles are per game and use the first connected controller; native forwarding
is preserved when the profile is disabled. Enabled profiles suppress duplicate
native input and send mapped gamepad output to player one.

Each stick can output Gamepad, Keys, Mouse or Off. Mouse speed and radial
deadzone are adjustable. For example, use Right Stick = Mouse, A = Mouse Left,
and B = Mouse Right. Modifiers are pressed before other mapped keys. Analog
trigger values are retained when mapped to Pad L2/R2. Disconnect, background,
menu and editor transitions release the inputs owned by the controller.

Extra-button support depends on [Apple's physical-input profile](https://developer.apple.com/documentation/gamecontroller/gcphysicalinputprofile/buttons).
Some 8BitDo modes/paddles duplicate standard buttons in firmware; the app cannot
invent separate inputs for buttons iOS does not expose. OS-reserved actions
and controller firmware remapping still apply.

Edit Controls supports up to four virtual joysticks. Tap a stick to configure
it, drag fixed sticks to position them, and Save the layout. For two floating
sticks, choose Left half and Right half touch regions. Choose axes 0/1 for
the left gamepad stick and 2/3 for the right, or assign direction keys. Distinct
touches can hold separate sticks/buttons at once. Input sources retain separate
axis contributions, so releasing one stick does not cancel another's hold.

Touch Gestures configures two-finger tap, three-finger tap and two-finger drag
scroll in Trackpad mouse mode. Tap bindings accept ordinary key names such as
Escape, Space, F5 or Mouse Right. Fixed virtual controls take precedence over
trackpad gestures; floating-stick regions consume their own touches. Direct
Touch retains its ordinary pointer behavior. Button/direction editors also
allow custom Godot key names.

Pins now has Edit Value. Save changes the stored name/value; Apply sends it to
the game and Freeze applies and holds it. Using Freeze again updates the
existing target rather than consuming another freeze slot. Numeric values stay
as text, including full 64-bit integers. Live edits retain the existing backup,
type validation and undo protections.

## Verification

Both desktop engines compiled and each executed 73 native checks. These cover
pin-freeze replacement/slot reuse, player-one remapped input/release and prior
input/stat/undo checks. Twenty-three Python/native helper tests pass, including
the real C++ PE scanner on original synthetic PE fixtures and malformed inputs.
The same scanner locates Coffee's previously verified key candidate, which
decrypts all 96 reference scripts with matching checksums. No key bytes are
included in the source package.

The Swift/Objective-C iPhone importer, runtime key handoff, controller hardware,
gesture delivery and multiple-touch UI still require Actions/device testing.
The macOS model tests are configured to run actual PE discovery and CommonCrypto
AES validation against an original encrypted-script fixture, reject wrong keys,
and check profile/pin/key persistence. The simulator compiles the actual
controller code and checks shared input-source release. No new IPA or verified
Coffee gameplay on iPhone was produced locally.
