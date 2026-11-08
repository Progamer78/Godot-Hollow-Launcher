import SwiftUI
import UIKit

struct JoystickEditor: View {
    @State var joystick: JoystickControl
    let onSave: (JoystickControl) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    var body: some View {
        NavigationView {
            Form {
                Picker("Position", selection: $joystick.mode) {
                    Text("Fixed").tag("fixed")
                    Text("Floating").tag("floating")
                }.pickerStyle(SegmentedPickerStyle())
                Text(joystick.mode == "floating" ? "The stick appears where you touch and follows your drag. Other control buttons stay available. Floating mode uses screen drags, so mouse mode is off." : "Drag the joystick in the control editor to choose its position.")
                    .font(.caption).foregroundColor(.secondary)
                Section(header: Text("Direction inputs")) {
                    Button("Use arrow keys") { joystick.up = "Up"; joystick.down = "Down"; joystick.left = "Left"; joystick.right = "Right" }
                    Button("Use WASD") { joystick.up = "W"; joystick.down = "S"; joystick.left = "A"; joystick.right = "D" }
                    keyPicker("Up", key: $joystick.up)
                    keyPicker("Down", key: $joystick.down)
                    keyPicker("Left", key: $joystick.left)
                    keyPicker("Right", key: $joystick.right)
                }
                Section(header: Text("Feel")) {
                    Text("Size: \(Int(joystick.diameter))")
                    Slider(value: $joystick.diameter, in: 90...220, step: 2)
                    Text("Deadzone: \(Int(joystick.deadzone * 100))%")
                    Slider(value: $joystick.deadzone, in: 0.08...0.5, step: 0.01)
                }
                Button("Remove Joystick", action: onDelete).foregroundColor(.red)
            }
            .navigationTitle("Joystick")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { joystick.constrain(); onSave(joystick) } }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func keyPicker(_ title: String, key: Binding<String>) -> some View {
        Picker(title, selection: key) { ForEach(ControlKeys.all, id: \.self) { Text($0).tag($0) } }
    }
}

struct JoystickSurface: UIViewRepresentable {
    let configuration: JoystickControl
    func makeUIView(context: Context) -> JoystickTouchView { JoystickTouchView() }
    func updateUIView(_ view: JoystickTouchView, context: Context) {
        if view.configuration != configuration { view.cancelTouch() }
        view.configuration = configuration
        view.setNeedsLayout()
    }
    static func dismantleUIView(_ view: JoystickTouchView, coordinator: ()) { view.cancelTouch() }
}

final class JoystickTouchView: UIView {
    var configuration = JoystickControl()
    private let ring = UIView()
    private let knob = UIView()
    private var activeTouch: UITouch?
    private var origin = CGPoint.zero
    private var held = Set<String>()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        ring.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        ring.layer.borderColor = UIColor.systemTeal.withAlphaComponent(0.75).cgColor
        ring.layer.borderWidth = 2
        knob.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.7)
        ring.isUserInteractionEnabled = false; knob.isUserInteractionEnabled = false
        addSubview(ring); addSubview(knob)
        accessibilityLabel = "Virtual joystick"
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTouch), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelTouch() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Resizing/rotation releases the owning touch instead of sticking a key.
        cancelTouch()
        if configuration.mode == "fixed" { origin = CGPoint(x: bounds.midX, y: bounds.midY) }
        drawStick(offset: .zero)
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if configuration.mode == "floating" { return bounds.contains(point) }
        return hypot(point.x - bounds.midX, point.y - bounds.midY) <= CGFloat(configuration.diameter / 2)
    }
    private func drawStick(offset: CGPoint) {
        let diameter = CGFloat(configuration.diameter)
        ring.frame = CGRect(x: origin.x - diameter / 2, y: origin.y - diameter / 2, width: diameter, height: diameter)
        ring.layer.cornerRadius = diameter / 2
        let size = diameter * 0.4
        knob.frame = CGRect(x: origin.x + offset.x - size / 2, y: origin.y + offset.y - size / 2, width: size, height: size)
        knob.layer.cornerRadius = size / 2
        ring.isHidden = configuration.mode == "floating" && activeTouch == nil
        knob.isHidden = ring.isHidden
    }
    private func update(_ point: CGPoint) {
        let radius = CGFloat(configuration.diameter * 0.34)
        let dx = point.x - origin.x, dy = point.y - origin.y
        let distance = hypot(dx, dy), scale = distance > radius ? radius / distance : 1
        let next = configuration.keys(dx: Double(dx / radius), dy: Double(dy / radius))
        for key in held.subtracting(next) { PlayerRuntime.setKey(key, pressed: false) }
        for key in next.subtracting(held) { PlayerRuntime.setKey(key, pressed: true) }
        held = next
        drawStick(offset: CGPoint(x: dx * scale, y: dy * scale))
    }
    @objc func cancelTouch() {
        for key in held { PlayerRuntime.setKey(key, pressed: false) }
        held.removeAll(); activeTouch = nil
        drawStick(offset: .zero)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        if configuration.mode == "floating" { origin = touch.location(in: self) }
        else { origin = CGPoint(x: bounds.midX, y: bounds.midY) }
        update(touch.location(in: self))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        update(touch.location(in: self))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { cancelTouch() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
}
