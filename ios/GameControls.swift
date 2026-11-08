import SwiftUI
import UIKit
import QuartzCore

private struct EngineView: UIViewControllerRepresentable {
    let controller: UIViewController
    let ratio: Double
    let orientation: String
    func makeUIViewController(context: Context) -> UIViewController {
        PlayerGameContainer(engine: controller, ratio: ratio, orientation: orientation)
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private final class PlayerGameContainer: UIViewController {
    let engine: UIViewController
    let ratio: Double
    let orientation: String
    init(engine: UIViewController, ratio: Double, orientation: String) {
        self.engine = engine; self.ratio = ratio; self.orientation = orientation
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(engine); view.addSubview(engine.view); engine.didMove(toParent: self)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let area = bounds.height > bounds.width ? view.safeAreaLayoutGuide.layoutFrame : bounds
        let fitted = GameViewport.frame(width: Double(area.width), height: Double(area.height), aspect: ratio)
        engine.view.frame = CGRect(x: area.minX + CGFloat(fitted.x), y: area.minY + CGFloat(fitted.y),
                                   width: CGFloat(fitted.width), height: CGFloat(fitted.height))
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 16.0, *) {
            view.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            let mask: UIInterfaceOrientationMask = orientation == "portrait" ? .portrait : (orientation == "landscape" ? .landscape : [.portrait, .landscape])
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                NSLog("Player orientation request: %@", error.localizedDescription)
            }
        } else { UIViewController.attemptRotationToDeviceOrientation() }
    }
    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientation == "portrait" ? .portrait : (orientation == "landscape" ? .landscape : [.portrait, .landscape])
    }
    override var prefersStatusBarHidden: Bool { true }
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
    @State private var editingJoystick = false
    @State private var showingTools = false
    @State private var controlArea = CGSize.zero
    @State private var needsInitialLayout: Bool
    @State private var menuOpen = false
    @State private var menuHeight: CGFloat = 220
    @AppStorage("playerMenuX") private var menuX = 1.0
    @AppStorage("playerMenuY") private var menuY = 0.0
    @GestureState private var menuTranslation = CGSize.zero

    init(session: GameSession) {
        self.session = session
        _profile = State(initialValue: session.game.controls)
        _showButtons = State(initialValue: session.game.showControls)
        _needsInitialLayout = State(initialValue: session.game.controlProfile == nil)
    }

    var body: some View {
        ZStack {
            EngineView(controller: session.controller, ratio: session.aspectRatio, orientation: session.game.displayOrientation)
                .ignoresSafeArea()
                .allowsHitTesting(!editing && !profile.mouseEnabled)
            if profile.mouseEnabled && !editing {
                MouseSurface(mode: profile.mouseMode, sensitivity: profile.mouseSensitivity).ignoresSafeArea()
            }
            if editing { Color.black.opacity(0.18).ignoresSafeArea() }
            GeometryReader { area in
                ZStack {
                    if let stick = profile.joystick, showButtons || editing { joystick(stick, in: area.size) }
                    if showButtons || editing {
                        ForEach(profile.buttons) { button in
                            control(button, in: area.size)
                        }
                    }
                    if menuOpen || editing { menuPanel(in: area.size) }
                    menuHandle(in: area.size)
                }
                .coordinateSpace(name: "playerControls")
                .onAppear { updateArea(area.size) }
                .onChange(of: area.size) { updateArea($0) }
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
        .sheet(isPresented: $editingJoystick) {
                JoystickEditor(joystick: profile.joystick ?? JoystickControl(), onSave: { updated in
                    profile.joystick = updated
                    if updated.mode == "floating" { profile.mouseEnabled = false }
                    editingJoystick = false
                }, onDelete: { profile.joystick = nil; editingJoystick = false }, onCancel: { editingJoystick = false })
        }
        .sheet(isPresented: $showingTools, onDismiss: {
            PlayerRuntime.setMouseEnabled(profile.mouseEnabled && !editing)
        }) { GameTools() }
        .onAppear { PlayerRuntime.setMouseEnabled(profile.mouseEnabled && !editing) }
        .onDisappear { PlayerRuntime.releaseKeys(); PlayerRuntime.setMouseEnabled(false) }
        .onChange(of: phase) { if $0 != .active { PlayerRuntime.releaseKeys() } }
    }

    private var menuContents: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                Text("Drag controls to move them. Tap one to edit its inputs or size.").font(.caption)
                HStack(spacing: 14) {
                    Button("Cancel") { cancelEdit() }
                    Button("Add Button") {
                        guard profile.buttons.count < 32 else { return }
                        let button = ControlButton(label: "Space", key: "Space", x: 0.5, y: 0.5)
                        profile.buttons.append(button)
                        selected = button
                    }.disabled(profile.buttons.count >= 32)
                    Button("Save") {
                        if library.saveControls(profile, visible: showButtons, for: session.id) {
                            editing = false
                            menuOpen = false
                            original = nil
                            PlayerRuntime.setMouseEnabled(profile.mouseEnabled)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button(profile.joystick == nil ? "Add Joystick" : "Edit Joystick") {
                        editingJoystick = true
                    }
                    Button("Reset Buttons") { resetButtons() }
                }
            } else {
                HStack(spacing: 16) {
                    Button(showButtons ? "Hide Controls" : "Show Controls") {
                        PlayerRuntime.releaseKeys()
                        if library.saveControls(profile, visible: !showButtons, for: session.id) {
                            showButtons.toggle()
                            menuOpen = false
                        }
                    }
                    Button(profile.mouseEnabled ? "Mouse: On" : "Mouse: Off") {
                        var updated = profile
                        updated.mouseEnabled.toggle()
                        if updated.mouseEnabled && updated.joystick?.mode == "floating" { updated.joystick?.mode = "fixed" }
                        if library.saveControls(updated, visible: showButtons, for: session.id) {
                            profile = updated
                            PlayerRuntime.setMouseEnabled(profile.mouseEnabled)
                            menuOpen = false
                        }
                    }
                }
                if profile.joystick?.mode == "floating" {
                    Text("Floating joystick: drag anywhere outside the buttons and menu. Mouse mode is off.").font(.caption)
                }
                Button("Edit Controls") {
                    PlayerRuntime.releaseKeys()
                    PlayerRuntime.setMouseEnabled(false)
                    original = profile
                    originalVisibility = showButtons
                    editing = true
                }
                Button {
                    PlayerRuntime.releaseKeys()
                    PlayerRuntime.setMouseEnabled(false)
                    menuOpen = false
                    showingTools = true
                } label: { Label("Game Tools · Cheats & Console", systemImage: "slider.horizontal.3") }
                if profile.mouseEnabled {
                    HStack(spacing: 16) {
                        Button(profile.mouseMode == "trackpad" ? "Trackpad" : "Direct Touch") {
                            var updated = profile
                            updated.mouseMode = updated.mouseMode == "trackpad" ? "direct" : "trackpad"
                            if library.saveControls(updated, visible: showButtons, for: session.id) {
                                PlayerRuntime.releaseKeys()
                                profile = updated
                                menuOpen = false
                            }
                        }
                        Button("Scroll ↑") { PlayerRuntime.scrollMouse(1) }
                        Button("Scroll ↓") { PlayerRuntime.scrollMouse(-1) }
                    }
                    HStack(spacing: 12) {
                        KeySurface(title: "Left Click", key: "Mouse Left").frame(width: 84, height: 44)
                        KeySurface(title: "Right Click", key: "Mouse Right").frame(width: 88, height: 44)
                    }
                }
                Text("Drag the ⋯ button to move it. Tap it to close this menu.").font(.caption)
            }
        }
        .padding(12).foregroundColor(.white)
        .background(Color.black.opacity(0.8)).cornerRadius(12)
    }

    private func menuPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(22, 22 + CGFloat(menuX) * max(0, size.width - 44) + menuTranslation.width), max(22, size.width - 22)),
                y: min(max(22, 22 + CGFloat(menuY) * max(0, size.height - 44) + menuTranslation.height), max(22, size.height - 22)))
    }

    private func joystickPoint(_ joystick: JoystickControl, in size: CGSize) -> CGPoint {
        let radius = CGFloat(joystick.diameter / 2)
        return CGPoint(x: min(max(radius, CGFloat(joystick.x) * size.width), max(radius, size.width - radius)),
                       y: min(max(radius, CGFloat(joystick.y) * size.height), max(radius, size.height - radius)))
    }

    @ViewBuilder
    private func joystick(_ stick: JoystickControl, in size: CGSize) -> some View {
        if editing {
            EditableControl(button: ControlButton(label: "Joystick", key: stick.mode == "floating" ? "Floating" : "Fixed",
                                                  x: stick.x, y: stick.y, width: stick.diameter, height: stick.diameter),
                            center: joystickPoint(stick, in: size), area: size,
                            onSelect: { editingJoystick = true }, onMove: { point in
                profile.joystick?.x = Double(point.x / max(1, size.width))
                profile.joystick?.y = Double(point.y / max(1, size.height))
            })
        } else if stick.mode == "floating" {
            JoystickSurface(configuration: stick).frame(width: size.width, height: size.height)
        } else {
            JoystickSurface(configuration: stick)
                .frame(width: CGFloat(stick.diameter), height: CGFloat(stick.diameter))
                .position(joystickPoint(stick, in: size))
        }
    }

    private func menuHandle(in size: CGSize) -> some View {
        Button {
            if !editing { menuOpen.toggle() }
        } label: {
            Image(systemName: editing ? "arrow.up.left.and.arrow.down.right" : (menuOpen ? "xmark" : "ellipsis"))
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(menuOpen || editing ? 0.65 : 0.25)).clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(editing ? "Move controls menu" : (menuOpen ? "Close controls menu" : "Open controls menu"))
        .accessibilityHint("Drag to move away from the game's buttons")
        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("playerControls"))
            .updating($menuTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                let x = 22 + CGFloat(menuX) * max(0, size.width - 44) + value.translation.width
                let y = 22 + CGFloat(menuY) * max(0, size.height - 44) + value.translation.height
                menuX = Double(min(1, max(0, (x - 22) / max(1, size.width - 44))))
                menuY = Double(min(1, max(0, (y - 22) / max(1, size.height - 44))))
            })
        .position(menuPoint(in: size))
    }

    private func menuPanel(in size: CGSize) -> some View {
        let point = menuPoint(in: size)
        let width = min(340, size.width)
        let height = min(menuHeight, max(44, size.height - 56))
        let top = point.y + 28 + height <= size.height ? point.y + 28 : point.y - 28 - height
        return ScrollView {
            menuContents.background(GeometryReader { measured in
                Color.clear.preference(key: MenuHeight.self, value: measured.size.height).allowsHitTesting(false)
            })
        }
        .frame(width: width, height: height)
        .onPreferenceChange(MenuHeight.self) { menuHeight = $0 }
        .position(x: min(max(width / 2, point.x), max(width / 2, size.width - width / 2)),
                  y: min(max(height / 2, top + height / 2), max(height / 2, size.height - height / 2)))
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
        menuOpen = false
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

private struct MenuHeight: PreferenceKey {
    static var defaultValue: CGFloat = 220
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
        .onTapGesture(perform: onSelect)
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("playerControls"))
            .updating($translation) { value, state, _ in state = value.translation }
            .onEnded { value in
                onMove(CGPoint(x: min(max(CGFloat(button.width) / 2, center.x + value.translation.width), max(CGFloat(button.width) / 2, area.width - CGFloat(button.width) / 2)),
                               y: min(max(CGFloat(button.height) / 2, center.y + value.translation.height), max(CGFloat(button.height) / 2, area.height - CGFloat(button.height) / 2))))
            })
        .accessibilityLabel("Edit \(button.label), mapped to \(button.key)")
        .accessibilityAddTraits(.isButton)
        .position(x: center.x + translation.width, y: center.y + translation.height)
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
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.systemTeal.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.6) }
    }
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
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemTeal.withAlphaComponent(0.45).cgColor
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
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
