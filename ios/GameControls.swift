import SwiftUI
import UIKit
import QuartzCore

private struct EngineView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

struct GameScreen: View {
    let session: GameSession
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.scenePhase) private var phase
    @State private var profile: ControlProfile
    @State private var showButtons: Bool
    @State private var editing = false
    @State private var original: ControlProfile?
    @State private var originalVisibility = true
    @State private var selected: ControlButton?
    @State private var controlArea = CGSize.zero
    @State private var needsInitialLayout: Bool

    init(session: GameSession) {
        self.session = session
        _profile = State(initialValue: session.game.controls)
        _showButtons = State(initialValue: session.game.showControls)
        _needsInitialLayout = State(initialValue: session.game.controlProfile == nil)
    }

    var body: some View {
        ZStack {
            EngineView(controller: session.controller)
                .ignoresSafeArea()
                .allowsHitTesting(!editing && !profile.mouseEnabled)
            if profile.mouseEnabled && !editing {
                MouseSurface(mode: profile.mouseMode, sensitivity: profile.mouseSensitivity).ignoresSafeArea()
            }
            if editing { Color.black.opacity(0.18).ignoresSafeArea() }
            VStack(spacing: 4) {
                toolbar
                if editing {
                    Text("Drag buttons to move them. Tap one to change its label, key or size. Save keeps this game's layout.")
                        .font(.caption).padding(6).background(Color.black.opacity(0.7)).foregroundColor(.white)
                }
                GeometryReader { area in
                    ZStack {
                        if showButtons || editing {
                            ForEach(profile.buttons) { button in
                                control(button, in: area.size)
                            }
                        }
                    }
                    .onAppear { updateArea(area.size) }
                    .onChange(of: area.size) { updateArea($0) }
                }
            }.padding(8)
        }
        .sheet(item: $selected) { button in
            ControlButtonEditor(button: button, onSave: { edited in
                if let index = profile.buttons.firstIndex(where: { $0.id == edited.id }) { profile.buttons[index] = edited }
                selected = nil
            }, onDelete: {
                profile.buttons.removeAll { $0.id == button.id }
                selected = nil
            }, onCancel: { selected = nil })
        }
        .onAppear { PlayerRuntime.setMouseEnabled(profile.mouseEnabled && !editing) }
        .onDisappear { PlayerRuntime.releaseKeys(); PlayerRuntime.setMouseEnabled(false) }
        .onChange(of: phase) { if $0 != .active { PlayerRuntime.releaseKeys() } }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if editing {
                    Button("Cancel") { cancelEdit() }
                    Button("Add Button") {
                        guard profile.buttons.count < 32 else { return }
                        let button = ControlButton(label: "Space", key: "Space", x: 0.5, y: 0.5)
                        profile.buttons.append(button)
                        selected = button
                    }.disabled(profile.buttons.count >= 32)
                    Button("Reset Layout") {
                        resetButtons()
                    }
                    Button("Save") {
                        if library.saveControls(profile, visible: showButtons, for: session.id) {
                            editing = false
                            original = nil
                            PlayerRuntime.setMouseEnabled(profile.mouseEnabled)
                        }
                    }
                } else {
                    Button(showButtons ? "Hide Buttons" : "Show Buttons") {
                        PlayerRuntime.releaseKeys()
                        if library.saveControls(profile, visible: !showButtons, for: session.id) { showButtons.toggle() }
                    }
                    Button(profile.mouseEnabled ? "Mouse: On" : "Mouse: Off") {
                        var updated = profile
                        updated.mouseEnabled.toggle()
                        if library.saveControls(updated, visible: showButtons, for: session.id) {
                            profile = updated
                            PlayerRuntime.setMouseEnabled(profile.mouseEnabled)
                        }
                    }
                    Button("Edit Controls") {
                        PlayerRuntime.releaseKeys()
                        PlayerRuntime.setMouseEnabled(false)
                        original = profile
                        originalVisibility = showButtons
                        editing = true
                    }
                    if profile.mouseEnabled {
                        Button(profile.mouseMode == "trackpad" ? "Trackpad" : "Direct Touch") {
                            var updated = profile
                            updated.mouseMode = updated.mouseMode == "trackpad" ? "direct" : "trackpad"
                            if library.saveControls(updated, visible: showButtons, for: session.id) {
                                PlayerRuntime.releaseKeys()
                                profile = updated
                            }
                        }
                        KeySurface(title: "Left Click", key: "Mouse Left").frame(width: 84, height: 44)
                        KeySurface(title: "Right Click", key: "Mouse Right").frame(width: 88, height: 44)
                        Button("Scroll ↑") { PlayerRuntime.scrollMouse(1) }
                        Button("Scroll ↓") { PlayerRuntime.scrollMouse(-1) }
                    }
                }
            }.padding(8)
        }
        .background(Color.black.opacity(0.75)).foregroundColor(.white).cornerRadius(10)
    }

    @ViewBuilder
    private func control(_ button: ControlButton, in size: CGSize) -> some View {
        let center = position(button, in: size)
        if editing {
            EditableControl(button: button, center: center, area: size, onSelect: { selected = button }, onMove: { point in
                if let index = profile.buttons.firstIndex(where: { $0.id == button.id }) {
                    profile.buttons[index].x = Double(point.x / max(1, size.width))
                    profile.buttons[index].y = Double(point.y / max(1, size.height))
                    profile.buttons[index].constrain()
                }
            })
        } else {
            KeySurface(title: button.label, key: button.key)
                .frame(width: CGFloat(button.width), height: CGFloat(button.height))
                .position(center)
        }
    }

    private func position(_ button: ControlButton, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(CGFloat(button.width) / 2, CGFloat(button.x) * size.width), max(CGFloat(button.width) / 2, size.width - CGFloat(button.width) / 2)),
                y: min(max(CGFloat(button.height) / 2, CGFloat(button.y) * size.height), max(CGFloat(button.height) / 2, size.height - CGFloat(button.height) / 2)))
    }

    private func cancelEdit() {
        if let original = original { profile = original }
        showButtons = originalVisibility
        original = nil
        editing = false
        PlayerRuntime.setMouseEnabled(profile.mouseEnabled)
    }

    private func updateArea(_ size: CGSize) {
        controlArea = size
        if needsInitialLayout && size.width > 0 && size.height > 0 {
            resetButtons()
            needsInitialLayout = false
        }
    }

    private func resetButtons() {
        profile.buttons = ControlProfile.legacy(directions: session.game.directionKeys, extras: session.game.extraKeys,
                                               areaWidth: Double(max(1, controlArea.width)), areaHeight: Double(max(1, controlArea.height))).buttons
    }
}

private struct EditableControl: View {
    let button: ControlButton
    let center: CGPoint
    let area: CGSize
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    @GestureState private var translation = CGSize.zero
    var body: some View {
        VStack(spacing: 2) {
            Text(button.label).lineLimit(1)
            Text(button.key).font(.caption2).lineLimit(1)
        }
        .frame(width: CGFloat(button.width), height: CGFloat(button.height))
        .background(Color.black.opacity(0.75)).foregroundColor(.white)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 2))
        .cornerRadius(10)
        .position(x: center.x + translation.width, y: center.y + translation.height)
        .onTapGesture(perform: onSelect)
        .gesture(DragGesture(minimumDistance: 6)
            .updating($translation) { value, state, _ in state = value.translation }
            .onEnded { value in
                onMove(CGPoint(x: min(max(CGFloat(button.width) / 2, center.x + value.translation.width), max(CGFloat(button.width) / 2, area.width - CGFloat(button.width) / 2)),
                               y: min(max(CGFloat(button.height) / 2, center.y + value.translation.height), max(CGFloat(button.height) / 2, area.height - CGFloat(button.height) / 2))))
            })
        .accessibilityLabel("Edit \(button.label), mapped to \(button.key)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ControlButtonEditor: View {
    @State var button: ControlButton
    let onSave: (ControlButton) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    var body: some View {
        NavigationView {
            Form {
                TextField("Button label", text: $button.label)
                Picker("Input", selection: $button.key) {
                    ForEach(ControlKeys.all.contains(button.key) ? ControlKeys.all : [button.key] + ControlKeys.all, id: \.self) { key in Text(key).tag(key) }
                }
                Section(header: Text("Size")) {
                    Text("Width: \(Int(button.width))")
                    Slider(value: $button.width, in: 44...160, step: 2)
                    Text("Height: \(Int(button.height))")
                    Slider(value: $button.height, in: 44...120, step: 2)
                }
                Button("Delete Button", action: onDelete).foregroundColor(.red)
            }
            .navigationTitle("Edit Button")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        button.label = String(button.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                        if button.label.isEmpty { button.label = button.key }
                        button.constrain()
                        onSave(button)
                    }
                }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

private final class KeyButton: UIButton {
    var mappedKey = ""
    private var pressedKey: String?
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard pressedKey == nil else { return false }
        pressedKey = mappedKey
        PlayerRuntime.setKey(mappedKey, pressed: true)
        isHighlighted = true
        return true
    }
    func release() {
        if let key = pressedKey { PlayerRuntime.setKey(key, pressed: false) }
        pressedKey = nil
        isHighlighted = false
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { release() }
    override func cancelTracking(with event: UIEvent?) { release() }
}

private struct KeySurface: UIViewRepresentable {
    let title: String
    let key: String
    func makeUIView(context: Context) -> KeyButton {
        let button = KeyButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        button.layer.cornerRadius = 10
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        return button
    }
    func updateUIView(_ button: KeyButton, context: Context) {
        if button.mappedKey != key { button.release() }
        button.mappedKey = key
        button.accessibilityLabel = "\(title), \(key)"
        button.setTitle(title, for: .normal)
    }
    static func dismantleUIView(_ button: KeyButton, coordinator: ()) { button.release() }
}

private struct MouseSurface: UIViewRepresentable {
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

private final class MouseTouchView: UIView {
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
        else if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(refreshCursor(_:)))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }
    func stop() { cancelTouch(); displayLink?.invalidate(); displayLink = nil }
    func cancelTouch() {
        if heldLeft { PlayerRuntime.setMouseButton(1, pressed: false) }
        heldLeft = false
        tracking = false
    }
    @objc private func refreshCursor(_ link: CADisplayLink) {
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
