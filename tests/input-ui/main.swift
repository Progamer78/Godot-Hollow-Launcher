import UIKit
import ObjectiveC

// Engine endpoints are recorded here; the UIKit views and GameInput are the
// actual app sources, not copies. This checks view lifetime and keyboard input,
// not Godot rendering or the native engine bridges.
enum PlayerRuntime {
    static var keyEvents: [(String, Bool)] = []
    static var cursorPolls = 0
    static var cursorPositionReads = 0
    static var cursorVisibilityReads = 0
    static func setKey(_ key: String, pressed: Bool) { keyEvents.append((key, pressed)) }
    static func releaseKeys() {}
    static func setMouseButton(_ button: Int, pressed: Bool) {}
    static func scrollMouse(_ direction: Int) {}
    static func mouseCaptured() -> Bool { false }
    static func mouseCursorRevision() -> UInt { cursorPolls += 1; return 1 }
    static func mouseCursorImage() -> UIImage? { nil }
    static func mouseCursorHotspot() -> CGPoint { .zero }
    static func mousePosition(in view: UIView) -> CGPoint { cursorPositionReads += 1; return CGPoint(x: 20, y: 20) }
    static func mouseCursorVisible() -> Bool { cursorVisibilityReads += 1; return true }
    static func moveMouse(_ point: CGPoint, from view: UIView, relative: Bool) {}
}
struct SmokeReply { let ok: Bool }
enum ToolsBridge {
    static var textChunks: [String] = []
    static var commands: [[String: Any]] = []
    static func send(_ command: [String: Any]) -> SmokeReply {
        commands.append(command)
        if let text = command["text"] as? String { textChunks.append(text) }
        return SmokeReply(ok: true)
    }
}

@main
final class InputSmokeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { print("PLAYER_INPUT_UI_FAIL: \(message)"); fflush(stdout); exit(1) }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; self.window = window; window.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.exercise(controller.view) }
        return true
    }
    private func exercise(_ root: UIView) {
        let unsafe = unsafeLifetimeSelectors(KeyButton.self)
        check(unsafe.isEmpty, "Control overrides object-lifetime selectors \(unsafe)")
        for index in 0..<100 {
            autoreleasepool {
                let button = KeyButton(type: .custom)
                button.mappedKey = "Space"; button.behavior = "toggle"
                button.setTitle("Input \(index)", for: .normal)
                root.addSubview(button)
                button.isHighlighted = true; button.isSelected = true
                button.resetHeldInputs()
                NotificationCenter.default.post(name: Notification.Name("GodotPlayerReleaseInputs"), object: nil)
                button.removeFromSuperview()
            }
        }
        print("PLAYER_INPUT_UI_CHECK: control lifetime PASS")
        let joystick = JoystickTouchView(frame: CGRect(x: 0, y: 0, width: 128, height: 128))
        joystick.configuration.output = "gamepad"
        root.addSubview(joystick)
        for _ in 0..<10 { joystick.setNeedsLayout(); joystick.layoutIfNeeded() }
        check(!ToolsBridge.commands.contains { ($0["kind"] as? String) == "axis" }, "Idle joystick layout must not inject controller events")
        let keyboard = GameKeyboardTextView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
        root.addSubview(keyboard)
        keyboard.text = "Aé🙂"; keyboard.textViewDidChange(keyboard)
        check(ToolsBridge.textChunks.joined() == "Aé🙂" && keyboard.text.isEmpty, "Committed Unicode must go directly to the game once")
        keyboard.deleteBackward()
        check(PlayerRuntime.keyEvents.count == 2 && PlayerRuntime.keyEvents[0].0 == "Backspace" && PlayerRuntime.keyEvents[0].1 && !PlayerRuntime.keyEvents[1].1, "Empty responder must forward Backspace press/release")
        ToolsBridge.textChunks = []
        let pasted = String(repeating: "é🙂", count: 1600)
        check(GameInput.text(pasted), "Long Unicode paste accepted")
        check(ToolsBridge.textChunks.joined() == pasted && ToolsBridge.textChunks.allSatisfy { $0.unicodeScalars.count <= 512 }, "Paste must preserve characters across bounded native requests")
        GameInput.key("Space", pressed: true); GameInput.axis(0, value: 0.7); GameInput.release()
        check(GameInput.debugKeys.isEmpty && GameInput.axes.isEmpty, "Focus cancellation clears input state")
        GameInput.axis(0,value:0.4,source:"left"); GameInput.axis(0,value:0.2,source:"right")
        check(abs((GameInput.axes[0] ?? 0)-0.6)<0.001,"Concurrent input sources combine axis state")
        GameInput.axis(0,value:0,source:"left")
        check(GameInput.axes[0] == 0.2,"Releasing one stick does not cancel another")
        GameInput.release()
        GameInput.outputDevice=0
        GameInput.key("Pad A",pressed:true); GameInput.release()
        check(ToolsBridge.commands.contains { ($0["device"] as? Int) == 0 && ($0["kind"] as? String) == "button" && ($0["pressed"] as? Bool) == false },"Controller profile release reaches player-one output")
        GameInput.outputDevice=nil
        print("PLAYER_INPUT_UI_CHECK: joystick, keyboard, Unicode and release PASS")
        let mouse = MouseTouchView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        root.addSubview(mouse)
        // Exercise the same updater used by the display-link callback directly.
        // Headless CI does not guarantee a rendered frame within a wall-clock
        // interval; lack of that frame is not evidence of a cursor crash.
        let before = PlayerRuntime.cursorPolls
        let positionsBefore = PlayerRuntime.cursorPositionReads
        let visibilityBefore = PlayerRuntime.cursorVisibilityReads
        mouse.updateCursor()
        check(PlayerRuntime.cursorPolls == before + 1 && PlayerRuntime.cursorPositionReads == positionsBefore + 1 && PlayerRuntime.cursorVisibilityReads == visibilityBefore + 1, "Cursor updater reads revision, position and visibility")
        check(mouse.subviews.first?.frame.origin == CGPoint(x: 20, y: 20) && mouse.subviews.first?.isHidden == false, "Cursor updater applies the game position and visibility to the view")
        print("PLAYER_INPUT_UI_CHECK: cursor state and view update PASS")
        DispatchQueue.main.async {
            mouse.stop(); mouse.removeFromSuperview()
            joystick.removeFromSuperview()
            keyboard.dismissKeyboard(notify: false); keyboard.removeFromSuperview()
            print("PLAYER_INPUT_UI_PASS: control construction/lifetime, cursor, keyboard, Unicode and release")
            fflush(stdout); exit(0)
        }
    }
}
