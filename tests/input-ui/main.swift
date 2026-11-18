import UIKit
import SwiftUI
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
    private var checkLog: [String] = []
    private func record(_ message: String) { checkLog.append(message); print(message); fflush(stdout) }
    private func finish(_ success: Bool, _ message: String) {
        record("PLAYER_INPUT_UI_\(success ? "PASS" : "FAIL"): \(message)")
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try checkLog.joined(separator: "\n").write(to: folder.appendingPathComponent("input-ui-result.log"), atomically: true, encoding: .utf8)
        } catch { print("Could not record input test result: \(error)") }
        fflush(stdout); exit(success ? 0 : 1)
    }
    private func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { finish(false, message) }
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
        record("PLAYER_INPUT_UI_CHECK: control lifetime PASS")
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
        record("PLAYER_INPUT_UI_CHECK: joystick, keyboard, Unicode and release PASS")
        let mouse = MouseTouchView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        root.addSubview(mouse)
        // Exercise the same updater used by the display-link callback directly.
        // Headless CI does not guarantee a rendered frame within a wall-clock
        // interval; lack of that frame is not evidence of a cursor crash.
        let before = PlayerRuntime.cursorPolls
        let positionsBefore = PlayerRuntime.cursorPositionReads
        let visibilityBefore = PlayerRuntime.cursorVisibilityReads
        mouse.updateCursor()
        var gestures = TouchGestures(); gestures.enabled = true; gestures.secondFingerClick = "right"
        mouse.configureGestures(gestures)
        check(mouse.gestureRecognizers?.allSatisfy { !$0.isEnabled } == true, "Second-finger click must disable conflicting recognizers without intercepting the pointer")
        gestures.secondFingerClick = nil
        mouse.configureGestures(gestures)
        check(mouse.gestureRecognizers?.contains { $0.isEnabled } == true, "Ordinary trackpad gestures resume when second-finger click is off")
        check(PlayerRuntime.cursorPolls == before + 1 && PlayerRuntime.cursorPositionReads == positionsBefore + 1 && PlayerRuntime.cursorVisibilityReads == visibilityBefore + 1, "Cursor updater reads revision, position and visibility")
        check(mouse.subviews.first?.frame.origin == CGPoint(x: 20, y: 20) && mouse.subviews.first?.isHidden == false, "Cursor updater applies the game position and visibility to the view")
        record("PLAYER_INPUT_UI_CHECK: cursor state and view update PASS")
        DispatchQueue.main.async {
            mouse.stop(); mouse.removeFromSuperview()
            joystick.removeFromSuperview()
            keyboard.dismissKeyboard(notify: false); keyboard.removeFromSuperview()
            self.exercisePinnedMonitor(root)
        }
    }

    private func exercisePinnedMonitor(_ root: UIView) {
        // Compare actual rendered pixels with an identical very long name but
        // different values. In the old combined/truncated Text both images
        // were identical: the value was entirely offscreen behind the name.
        let name = String(repeating: "/root/GlobalState.characters.relationships.long_variable_name", count: 20)
        let pinID = UUID()
        let host = UIHostingController(rootView: HollowPinnedHUD(rows: [PinnedReadout(id: pinID, name: name, value: "12345")]))
        window?.rootViewController?.addChild(host)
        host.view.frame = CGRect(x: 0, y: 140, width: 240, height: 110)
        host.view.backgroundColor = .black
        root.addSubview(host.view); host.didMove(toParent: window?.rootViewController)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        func rendered() -> UIImage {
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
            return UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
                self.check(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true), "Pin monitor renders into the test image")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let firstImage = rendered()
            host.rootView = HollowPinnedHUD(rows: [PinnedReadout(id: pinID, name: name, value: "98765")])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let secondImage = rendered()
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? firstImage.pngData()?.write(to: folder.appendingPathComponent("hud-long-name-first.png"))
                try? secondImage.pngData()?.write(to: folder.appendingPathComponent("hud-long-name-second.png"))
                guard let first = firstImage.cgImage?.dataProvider?.data, let second = secondImage.cgImage?.dataProvider?.data else {
                    self.finish(false, "Pin monitor pixel data unavailable"); return
                }
                let a = first as Data, b = second as Data
                self.check(a.count == b.count, "Pin monitor rendering has consistent pixel dimensions")
                let changed = zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
                self.check(changed > 100, "Long pin name must leave the changing value visible (changed bytes: \(changed))")
                self.record("PLAYER_INPUT_UI_CHECK: long-name pin monitor values visible PASS (\(changed) changed pixel bytes)")
                host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
                self.finish(true, "control construction/lifetime, cursor, keyboard, Unicode, release and long-name pinned HUD values")
            }
        }
    }
}
