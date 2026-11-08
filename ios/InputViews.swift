import SwiftUI
import UIKit
import QuartzCore

final class KeyButton: UIButton {
    // Never expose a callback as Objective-C `release`: UIKit/ARC use that
    // selector for object lifetime, including during view construction.
    var mappedKey = ""
    var extraKeys: [String] = []
    var behavior = "hold"
    var haptics = false
    private var heldKeys: [String] = []
    private var repeatTimer: Timer?
    private var orderedKeys: [String] {
        let modifiers = ["Shift", "Control", "Alt", "Meta"]
        return Array(Set([mappedKey] + extraKeys)).sorted {
            let left = modifiers.firstIndex(of: $0) ?? 100, right = modifiers.firstIndex(of: $1) ?? 100
            return left == right ? $0 < $1 : left < right
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(resetHeldInputs), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetHeldInputs), name: Notification.Name("GodotPlayerReleaseInputs"), object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { repeatTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    override var isHighlighted: Bool {
        didSet { refreshAppearance() }
    }
    override var isSelected: Bool { didSet { refreshAppearance() } }
    private func refreshAppearance() { backgroundColor = isHighlighted || isSelected ? UIColor.systemTeal.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.6) }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if behavior == "toggle", !heldKeys.isEmpty { resetHeldInputs(); return true }
        guard heldKeys.isEmpty else { return false }
        let keys = orderedKeys
        for key in keys { GameInput.key(key, pressed: true) }
        heldKeys = keys
        if behavior == "toggle" { isSelected = true; accessibilityValue = "On" }
        if behavior == "repeat" {
            for key in heldKeys.reversed() { GameInput.key(key, pressed: false) }; heldKeys = []
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                for key in self.orderedKeys { GameInput.key(key, pressed: true) }
                for key in self.orderedKeys.reversed() { GameInput.key(key, pressed: false) }
            }
            repeatTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        isHighlighted = true
        return true
    }
    @objc func resetHeldInputs() {
        repeatTimer?.invalidate(); repeatTimer = nil
        for key in heldKeys.reversed() { GameInput.key(key, pressed: false) }
        heldKeys = []
        isSelected = false; accessibilityValue = behavior == "toggle" ? "Off" : nil
        isHighlighted = false
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { if behavior != "toggle" { resetHeldInputs() } }
    override func cancelTracking(with event: UIEvent?) { resetHeldInputs() }
}

struct KeySurface: UIViewRepresentable {
    let title: String
    let key: String
    var configuration: ControlButton? = nil
    var highContrast = false
    var haptics = false
    func makeUIView(context: Context) -> KeyButton {
        let button = KeyButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        button.layer.cornerRadius = 10
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemTeal.withAlphaComponent(0.45).cgColor
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        return button
    }
    func updateUIView(_ button: KeyButton, context: Context) {
        if button.mappedKey != key || button.extraKeys != (configuration?.combo ?? []) || button.behavior != (configuration?.behavior ?? "hold") { button.resetHeldInputs() }
        button.mappedKey = key
        button.extraKeys = configuration?.combo ?? []; button.behavior = configuration?.behavior ?? "hold"; button.haptics = haptics
        button.layer.borderWidth = highContrast ? 3 : 1
        button.layer.borderColor = highContrast ? UIColor.white.cgColor : UIColor.systemTeal.withAlphaComponent(0.45).cgColor
        button.accessibilityLabel = "\(title), \(key)"
        button.setTitle(title, for: .normal)
    }
    static func dismantleUIView(_ button: KeyButton, coordinator: ()) { button.resetHeldInputs() }
}

struct MouseSurface: UIViewRepresentable {
    let mode: String
    let sensitivity: Double
    func makeUIView(context: Context) -> MouseTouchView { MouseTouchView() }
    func updateUIView(_ view: MouseTouchView, context: Context) {
        if view.mode != mode { view.cancelTouch() }
        view.mode = mode
        view.sensitivity = CGFloat(sensitivity)
    }
    static func dismantleUIView(_ view: MouseTouchView, coordinator: ()) { view.stop() }
}

final class MouseTouchView: UIView {
    var mode = "trackpad"
    var sensitivity: CGFloat = 1
    private var last = CGPoint.zero
    private var distance: CGFloat = 0
    private var heldLeft = false
    private var tracking = false
    private var displayLink: CADisplayLink?
    private let cursor = UIImageView()
    private let arrow = CAShapeLayer()
    private var cursorRevision: UInt = 0
    private var hotspot = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        cursor.isUserInteractionEnabled = false
        addSubview(cursor)
        let path = UIBezierPath()
        path.move(to: .zero); path.addLine(to: CGPoint(x: 1, y: 24)); path.addLine(to: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 12, y: 28)); path.addLine(to: CGPoint(x: 17, y: 25)); path.addLine(to: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 21, y: 15)); path.close()
        arrow.path = path.cgPath
        arrow.fillColor = UIColor.white.cgColor
        arrow.strokeColor = UIColor.black.cgColor
        arrow.lineWidth = 1.5
        cursor.layer.addSublayer(arrow)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTouch), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTouch), name: Notification.Name("GodotPlayerReleaseInputs"), object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { displayLink?.invalidate(); NotificationCenter.default.removeObserver(self) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
        else if displayLink == nil {
            updateCursor()
            let link = CADisplayLink(target: self, selector: #selector(refreshCursor(_:)))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }
    func stop() { cancelTouch(); displayLink?.invalidate(); displayLink = nil }
    @objc func cancelTouch() {
        if heldLeft { PlayerRuntime.setMouseButton(1, pressed: false) }
        heldLeft = false
        tracking = false
    }
    @objc private func refreshCursor(_ link: CADisplayLink) {
        updateCursor()
    }
    // Also take an initial snapshot on attachment. Cursor state is useful even
    // before the display scheduler delivers the first animation callback.
    func updateCursor() {
        let revision = PlayerRuntime.mouseCursorRevision()
        if revision != cursorRevision {
            cursorRevision = revision
            cursor.image = PlayerRuntime.mouseCursorImage()
            arrow.isHidden = cursor.image != nil
            hotspot = PlayerRuntime.mouseCursorHotspot()
        }
        let point = PlayerRuntime.mousePosition(in: self)
        let size = cursor.image?.size ?? CGSize(width: 24, height: 30)
        cursor.frame = CGRect(x: point.x - hotspot.x, y: point.y - hotspot.y, width: size.width, height: size.height)
        cursor.isHidden = !PlayerRuntime.mouseCursorVisible()
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        last = touch.location(in: self)
        distance = 0
        tracking = true
        if mode == "direct" && !PlayerRuntime.mouseCaptured() {
            PlayerRuntime.moveMouse(last, from: self, relative: false)
            PlayerRuntime.setMouseButton(1, pressed: true)
            heldLeft = true
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking, let touch = touches.first else { return }
        let point = touch.location(in: self)
        let delta = CGPoint(x: point.x - last.x, y: point.y - last.y)
        distance += hypot(delta.x, delta.y)
        if mode == "direct" && !PlayerRuntime.mouseCaptured() { PlayerRuntime.moveMouse(point, from: self, relative: false) }
        else { PlayerRuntime.moveMouse(CGPoint(x: delta.x * sensitivity, y: delta.y * sensitivity), from: self, relative: true) }
        last = point
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking else { return }
        if !heldLeft && distance < 8 {
            PlayerRuntime.setMouseButton(1, pressed: true)
            PlayerRuntime.setMouseButton(1, pressed: false)
        }
        cancelTouch()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelTouch() }
}
