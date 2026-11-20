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
    var gestures=TouchGestures()
    func makeUIView(context: Context) -> MouseTouchView { MouseTouchView() }
    func updateUIView(_ view: MouseTouchView, context: Context) {
        if view.mode != mode { view.cancelTouch() }
        view.mode = mode
        view.sensitivity = CGFloat(sensitivity)
        view.configureGestures(gestures)
    }
    static func dismantleUIView(_ view: MouseTouchView, coordinator: ()) { view.stop() }
}

final class MouseTouchView: UIView, UIGestureRecognizerDelegate {
    private var gestureProfile=TouchGestures()
    private var gestureRecognizersOwned: [UIGestureRecognizer]=[]
    private var wheel = MouseWheelMotion()
    private var edgeTouch: UITouch?
    private var edgeLastY: CGFloat = 0
    private let edgeIndicator = UIView()
    var mode = "trackpad"
    var sensitivity: CGFloat = 1
    private var last = CGPoint.zero
    private var distance: CGFloat = 0
    private var heldButton: Int?
    private var cameraTouch = false
    private var tracking = false
    private var primaryTouch: UITouch?
    private var secondTouch: UITouch?
    private var secondOrigin = CGPoint.zero
    private var secondDistance: CGFloat = 0
    private var secondStarted: TimeInterval = 0
    private var secondFingerEnabled: Bool { mode == "trackpad" && gestureProfile.secondFingerButton != nil }
    private var dragOrigin = CGPoint.zero
    private var dragActive = false
    private var dragEnabled: Bool { gestureProfile.enabled && gestureProfile.twoFingerDrag == true && mode == "trackpad" && !secondFingerEnabled }
    private var displayLink: CADisplayLink?
    private let cursor = UIImageView()
    private let arrow = CAShapeLayer()
    private var cursorRevision: UInt = 0
    private var hotspot = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        edgeIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        edgeIndicator.layer.cornerRadius = 2; edgeIndicator.isUserInteractionEnabled = false
        cursor.isUserInteractionEnabled = false
        addSubview(cursor)
        addSubview(edgeIndicator)
        let path = UIBezierPath()
        path.move(to: .zero); path.addLine(to: CGPoint(x: 1, y: 24)); path.addLine(to: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 12, y: 28)); path.addLine(to: CGPoint(x: 17, y: 25)); path.addLine(to: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 21, y: 15)); path.close()
        arrow.path = path.cgPath
        arrow.fillColor = UIColor.white.cgColor
        arrow.strokeColor = UIColor.black.cgColor
        arrow.lineWidth = 1.5
        cursor.layer.addSublayer(arrow)
        let two=UITapGestureRecognizer(target:self,action:#selector(twoFingerTap)); two.numberOfTouchesRequired=2
        let doubleTwo=UITapGestureRecognizer(target:self,action:#selector(twoFingerDoubleTap)); doubleTwo.numberOfTouchesRequired=2; doubleTwo.numberOfTapsRequired=2
        two.require(toFail:doubleTwo)
        let three=UITapGestureRecognizer(target:self,action:#selector(threeFingerTap)); three.numberOfTouchesRequired=3
        two.require(toFail:three)
        let pan=UIPanGestureRecognizer(target:self,action:#selector(scrollGesture(_:))); pan.minimumNumberOfTouches=2; pan.maximumNumberOfTouches=2
        gestureRecognizersOwned=[two,three,doubleTwo,pan]
        for recognizer in gestureRecognizersOwned { recognizer.delegate = self; recognizer.isEnabled=false; addGestureRecognizer(recognizer) }
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTouch), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTouch), name: Notification.Name("GodotPlayerReleaseInputs"), object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configureGestures(_ value: TouchGestures) {
        if gestureProfile != value { cancelTouch() }
        gestureProfile=value
        setNeedsLayout()
        for recognizer in gestureRecognizersOwned { recognizer.isEnabled=value.enabled && mode == "trackpad" && !secondFingerEnabled }
        gestureRecognizersOwned.last?.isEnabled=value.enabled && value.scroll && mode == "trackpad" && !secondFingerEnabled && !dragEnabled
    }
    private func gestureKey(_ key: String) { cancelTouch(); if !key.isEmpty && key != "None" { GameInput.key(key,pressed:true); GameInput.key(key,pressed:false) } }
    @objc private func twoFingerTap() { gestureKey(gestureProfile.twoFingerTap) }
    @objc private func twoFingerDoubleTap() { gestureKey(gestureProfile.twoFingerDoubleTap ?? "Mouse Right") }
    @objc private func threeFingerTap() { gestureKey(gestureProfile.threeFingerTap) }
    @objc private func scrollGesture(_ gesture: UIPanGestureRecognizer) {
        cancelTouch()
        if gesture.state == .began { wheel.reset() }
        let delta=gesture.translation(in:self).y; gesture.setTranslation(.zero,in:self)
        sendWheel(delta)
    }
    private func sendWheel(_ delta: CGFloat) {
        let steps = wheel.steps(delta: Double(delta), profile: gestureProfile)
        for _ in 0..<abs(steps) { PlayerRuntime.scrollMouse(steps > 0 ? 1 : -1) }
    }
    private func inScrollStrip(_ point: CGPoint) -> Bool {
        guard mode == "trackpad", let edge = gestureProfile.edgeScroll else { return false }
        let width = CGFloat(gestureProfile.edgeScrollWidth ?? 36)
        return edge == "left" ? point.x < width : point.x >= bounds.width - width
    }
    private func inCameraArea(_ point: CGPoint) -> Bool {
        mode == "trackpad" && (gestureProfile.cameraLook == "full" || (gestureProfile.cameraLook == "right" && point.x >= bounds.width / 2))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !inScrollStrip(touch.location(in: self)) && !inCameraArea(touch.location(in: self))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        edgeIndicator.isHidden = mode != "trackpad" || gestureProfile.edgeScroll == nil
        let width = CGFloat(gestureProfile.edgeScrollWidth ?? 36)
        let x = gestureProfile.edgeScroll == "left" ? width / 2 : bounds.width - width / 2
        edgeIndicator.frame = CGRect(x: x - 2, y: bounds.height * 0.3, width: 4, height: bounds.height * 0.4)
    }
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
        if let button = heldButton { PlayerRuntime.setMouseButton(button, pressed: false) }
        heldButton = nil
        dragActive = false
        tracking = false
        primaryTouch = nil; secondTouch = nil
        edgeTouch = nil; cameraTouch = false
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
            hotspot = cursor.image == nil ? .zero : PlayerRuntime.mouseCursorHotspot()
        }
        let point = PlayerRuntime.mousePosition(in: self)
        let size = cursor.image?.size ?? CGSize(width: 24, height: 30)
        cursor.frame = CGRect(x: point.x - hotspot.x, y: point.y - hotspot.y, width: size.width, height: size.height)
        cursor.isHidden = cameraTouch || !PlayerRuntime.mouseCursorVisible()
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var touches = touches
        if edgeTouch == nil, let touch = touches.first(where: { inScrollStrip($0.location(in: self)) }) {
            edgeTouch = touch; edgeLastY = touch.location(in: self).y; wheel.reset()
            touches.remove(touch)
        }
        if touches.isEmpty { return }
        if cameraTouch && tracking { return }
        if secondFingerEnabled || dragEnabled, tracking, let primary = primaryTouch {
            if activeTouches(event, fallback: touches) > 2 { secondDistance = .infinity; return }
            if secondTouch == nil, let touch = touches.first(where: { $0 !== primary }) {
                secondTouch = touch; secondOrigin = touch.location(in: self)
                secondDistance = 0; secondStarted = touch.timestamp; dragOrigin = secondOrigin
                // Ending the pointer finger after a secondary click must not
                // also produce the ordinary one-finger tap click.
                distance = max(8, distance)
            }
            return
        }
        guard activeTouches(event, fallback:touches) == 1 else { cancelTouch(); return }
        guard let touch = touches.first else { return }
        last = touch.location(in: self)
        distance = 0
        tracking = true
        primaryTouch = touch
        cameraTouch = inCameraArea(last)
        if cameraTouch {
            heldButton = gestureProfile.cameraMouseButton
            if let button = heldButton { PlayerRuntime.setMouseButton(button, pressed: true) }
            return
        }
        if mode == "direct" && !PlayerRuntime.mouseCaptured() {
            PlayerRuntime.moveMouse(last, from: self, relative: false)
            PlayerRuntime.setMouseButton(1, pressed: true)
            heldButton = 1
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let edge = edgeTouch, touches.contains(edge) {
            let y = edge.location(in: self).y; sendWheel(y - edgeLastY); edgeLastY = y
            if touches.count == 1 { return }
        }
        if let second = secondTouch, touches.contains(second) {
            let point = second.location(in: self)
            secondDistance = max(secondDistance, hypot(point.x - secondOrigin.x, point.y - secondOrigin.y))
        }
        if dragEnabled, let second = secondTouch {
            guard activeTouches(event, fallback: touches) <= 2 else { cancelTouch(); return }
            if touches.contains(second) {
                let point = second.location(in: self)
                let delta = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
                if !dragActive && hypot(point.x - secondOrigin.x, point.y - secondOrigin.y) >= 6 {
                    dragActive = true; heldButton = gestureProfile.dragMouseButton
                    PlayerRuntime.setMouseButton(gestureProfile.dragMouseButton, pressed: true)
                }
                if dragActive { PlayerRuntime.moveMouse(CGPoint(x: delta.x * sensitivity, y: delta.y * sensitivity), from: self, relative: true) }
                dragOrigin = point
            }
            return
        }
        if !cameraTouch && !secondFingerEnabled && activeTouches(event, fallback:touches) != 1 { cancelTouch(); return }
        guard tracking, let touch = primaryTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        let delta = CGPoint(x: point.x - last.x, y: point.y - last.y)
        distance += hypot(delta.x, delta.y)
        if mode == "direct" && !PlayerRuntime.mouseCaptured() { PlayerRuntime.moveMouse(point, from: self, relative: false) }
        else { PlayerRuntime.moveMouse(CGPoint(x: delta.x * sensitivity, y: delta.y * sensitivity), from: self, relative: true) }
        last = point
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let edge = edgeTouch, touches.contains(edge) { edgeTouch = nil; wheel.reset() }
        if dragEnabled, let second = secondTouch, touches.contains(second) {
            if let button = heldButton { PlayerRuntime.setMouseButton(button, pressed: false) }
            heldButton = nil; dragActive = false; secondTouch = nil
            distance = max(8, distance)
        }
        if secondFingerEnabled, let second = secondTouch, touches.contains(second) {
            let final = second.location(in: self)
            secondDistance = max(secondDistance, hypot(final.x - secondOrigin.x, final.y - secondOrigin.y))
            if tracking, let primary = primaryTouch, primary.phase != .ended, primary.phase != .cancelled,
               secondDistance <= 12, second.timestamp - secondStarted <= 0.5, let button = gestureProfile.secondFingerButton {
                PlayerRuntime.setMouseButton(button, pressed: true)
                PlayerRuntime.setMouseButton(button, pressed: false)
            }
            secondTouch = nil
        }
        guard let primary = primaryTouch, touches.contains(primary) else { return }
        guard tracking else { return }
        if !cameraTouch && heldButton == nil && distance < 8 {
            PlayerRuntime.setMouseButton(1, pressed: true)
            PlayerRuntime.setMouseButton(1, pressed: false)
        }
        cancelTouch()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let edge = edgeTouch, touches.contains(edge) { edgeTouch = nil; wheel.reset() }
        if let primary = primaryTouch, touches.contains(primary) { cancelTouch() }
        else if let second = secondTouch, touches.contains(second) { cancelTouch() }
    }
    private func activeTouches(_ event: UIEvent?, fallback: Set<UITouch>) -> Int {
        // A finger holding a virtual key or a different joystick belongs to
        // that view, not to this trackpad's gesture. Keep those inputs concurrent.
        (event?.touches(for:self) ?? fallback).filter { $0 !== edgeTouch && $0.phase != .ended && $0.phase != .cancelled }.count
    }
}
