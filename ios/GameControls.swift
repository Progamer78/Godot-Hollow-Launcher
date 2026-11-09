import SwiftUI
import UIKit
import QuartzCore

private struct EngineView: UIViewControllerRepresentable {
    let controller: UIViewController
    let ratio: Double
    let orientation: String
    let inset: Double
    func makeUIViewController(context: Context) -> UIViewController {
        PlayerGameContainer(engine: controller, ratio: ratio, orientation: orientation, inset: inset)
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private final class PlayerGameContainer: UIViewController {
    let engine: UIViewController
    let ratio: Double
    let orientation: String
    let inset: Double
    init(engine: UIViewController, ratio: Double, orientation: String, inset: Double) {
        self.engine = engine; self.ratio = ratio; self.orientation = orientation; self.inset = inset.isFinite ? min(48, max(0, inset)) : 0
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
        let area = (bounds.height > bounds.width || inset > 0 ? view.safeAreaLayoutGuide.layoutFrame : bounds).insetBy(dx: CGFloat(inset), dy: CGFloat(inset))
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
    @State private var editingStickID: UUID?
    @State private var showingController = false
    @State private var showingGestures = false
    @StateObject private var controllerInput = ControllerInput()
    @State private var showingTools = false
    @State private var controlArea = CGSize.zero
    @State private var needsInitialLayout: Bool
    @State private var menuOpen = false
    @State private var showingKeyboard = false
    @State private var debuggingInput = false
    @State private var inputStatus = ""
    @State private var launchReady = false
    @State private var sessionStart = Date()
    @State private var lastTick = Date.distantPast
    @State private var wasActive = true
    private let heartbeat = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
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

    private var mouseActive: Bool {
        launchReady && phase == .active && (profile.mouseEnabled || profile.controller?.mouseEnabled == true) && !editing && !showingKeyboard && !showingTools && !showingController && !showingGestures
    }

    private func syncMouseMode() { controllerInput.stop(); PlayerRuntime.setMouseEnabled(mouseActive) }

    var body: some View {
        ZStack {
            EngineView(controller: session.controller, ratio: session.aspectRatio, orientation: session.game.displayOrientation, inset: session.game.displayInset ?? 0)
                .ignoresSafeArea()
                .allowsHitTesting(!editing && !(mouseActive && profile.mouseEnabled))
            if mouseActive {
                MouseSurface(mode: profile.mouseMode, sensitivity: profile.mouseSensitivity, gestures: profile.gestures ?? TouchGestures()).ignoresSafeArea().allowsHitTesting(profile.mouseEnabled)
            }
            if editing { Color.black.opacity(0.18).ignoresSafeArea() }
            GeometryReader { area in
                ZStack {
                    if showButtons || editing { ForEach(profile.sticks) { stick in joystick(stick, in: area.size) } }
                    if showButtons || editing {
                        ForEach(profile.buttons) { button in
                            control(button, in: area.size)
                                .opacity(profile.opacity ?? 0.85)
                        }
                    }
                    if menuOpen || editing { menuPanel(in: area.size) }
                    menuHandle(in: area.size)
                    if debuggingInput {
                        Text(inputStatus).font(.system(.caption2, design: .monospaced)).padding(6).background(Color.black.opacity(0.75)).foregroundColor(.green).allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .coordinateSpace(name: "playerControls")
                .onAppear { updateArea(area.size) }
                .onChange(of: area.size) { updateArea($0) }
            }.padding(8)
            if showingKeyboard {
                GameKeyboardCapture(onClose: { showingKeyboard = false })
                    .frame(width: 1, height: 1).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: showingKeyboard) { _ in syncMouseMode() }
        .onChange(of: launchReady) { _ in syncMouseMode() }
        .onChange(of: showingController) { _ in syncMouseMode() }
        .onChange(of: showingTools) { _ in syncMouseMode() }
        .onChange(of: editing) { _ in syncMouseMode() }
        .onChange(of: showingGestures) { _ in syncMouseMode() }
        .onChange(of: menuOpen) { if $0 { controllerInput.stop() } }
        .sheet(isPresented:$showingGestures) {
            GestureEditor(value:profile.gestures ?? TouchGestures(),onSave:{ value in
                profile.gestures=value
                _ = library.saveControls(profile,visible:showButtons,for:session.id)
            })
        }
        .sheet(isPresented:$showingController,onDismiss:{
            profile=(library.games.first { $0.id == session.id } ?? session.game).controls
            GameInput.release(); GameInput.outputDevice=profile.controller?.enabled == true ? 0 : nil; PlayerRuntime.configureController(profile.controller?.enabled == true); syncMouseMode()
        }) {
            ControllerEditor(profile:profile.controller ?? ControllerProfile(),onSave:{ updated in
                var value=profile; value.controller=updated
                _ = library.saveControls(value,visible:showButtons,for:session.id)
            })
        }
        .onReceive(heartbeat) { now in
            guard phase == .active else { return }
            controllerInput.configure(profile.controller,active:launchReady && !editing && !menuOpen && !showingTools && !showingKeyboard && !showingController && !showingGestures,view:session.controller.view)
            if launchReady { _ = ToolsBridge.send(["action": "tick"]) }
            if now.timeIntervalSince(lastTick) >= 1 {
                lastTick = now
                let status = ToolsBridge.send(["action": "status"])
                if !launchReady, status.ready == true {
                    launchReady = true; library.journal(session.game, status: "running"); library.markPlayed(session.id)
                    if let fps = session.game.frameLimit, fps != 0 { _ = ToolsBridge.send(["action": "options", "fps": fps]) }
                }
                if debuggingInput { inputStatus = "Keys: \(GameInput.debugKeys.sorted().joined(separator: ", "))\nAxes: \(GameInput.axes.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: " "))\n\(status.message ?? "loading")" }
            }
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
                JoystickEditor(joystick: profile.sticks.first { $0.id == editingStickID } ?? JoystickControl(), onSave: { updated in
                    if profile.joystick?.id == updated.id { profile.joystick = updated }
                    else if let index=profile.additionalJoysticks?.firstIndex(where: { $0.id == updated.id }) { profile.additionalJoysticks?[index]=updated }
                    if updated.mode == "floating" { profile.mouseEnabled = false }
                    editingJoystick = false
                }, onDelete: {
                    if profile.joystick?.id == editingStickID { profile.joystick=nil }
                    profile.additionalJoysticks?.removeAll { $0.id == editingStickID }; editingJoystick=false
                }, onCancel: { editingJoystick = false })
        }
        .sheet(isPresented: $showingTools, onDismiss: {
            syncMouseMode()
        }) { GameTools(gameID: session.id) }
        .onAppear { GameInput.outputDevice=profile.controller?.enabled == true ? 0 : nil; syncMouseMode() }
        .onDisappear { controllerInput.stop(); GameInput.release(); PlayerRuntime.setMouseEnabled(false) }
        .onChange(of: phase) { value in
            if value != .active {
                controllerInput.stop()
                showingKeyboard = false
                PlayerRuntime.setMouseEnabled(false)
                GameInput.release()
                library.journal(session.game, status: launchReady ? "backgrounded" : "starting")
                if wasActive { library.markPlayed(session.id, seconds: Date().timeIntervalSince(sessionStart)); wasActive = false }
            } else { wasActive = true; sessionStart = Date(); syncMouseMode(); if launchReady { library.journal(session.game, status: "running") } }
        }
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
                            syncMouseMode()
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button("Add Joystick") {
                        guard profile.sticks.count < 4 else { return }
                        var stick=JoystickControl(); stick.identifier=UUID()
                        stick.x=profile.sticks.isEmpty ? 0.2 : 0.8
                        stick.zone=profile.sticks.isEmpty ? "left" : "right"
                        stick.axis=profile.sticks.isEmpty ? 0 : 2
                        if profile.joystick == nil { profile.joystick=stick } else { profile.additionalJoysticks=(profile.additionalJoysticks ?? [])+[stick] }
                        editingStickID=stick.id
                        editingJoystick = true
                    }.disabled(profile.sticks.count >= 4)
                    Button("Reset Buttons") { resetButtons() }
                }
            } else {
                HStack(spacing: 16) {
                    Button(showButtons ? "Hide Controls" : "Show Controls") {
                        GameInput.release()
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
                            syncMouseMode()
                            menuOpen = false
                        }
                    }
                }
                if profile.joystick?.mode == "floating" {
                    Text("Floating joystick: drag anywhere outside the buttons and menu. Mouse mode is off.").font(.caption)
                }
                Button("Edit Controls") {
                    GameInput.release()
                    PlayerRuntime.setMouseEnabled(false)
                    original = profile
                    originalVisibility = showButtons
                    editing = true
                }
                Group {
                    Button("Keyboard") { GameInput.release(); PlayerRuntime.setMouseEnabled(false); menuOpen = false; showingKeyboard = true }.disabled(!launchReady)
                    Button("Controller Bindings") { controllerInput.stop(); GameInput.release(); PlayerRuntime.configureController(true); menuOpen=false; showingController=true }
                    Button("Touch Gestures") { controllerInput.stop(); GameInput.release(); menuOpen=false; showingGestures=true }
                }
                Button(debuggingInput ? "Hide Input Monitor" : "Show Input Monitor") { debuggingInput.toggle(); menuOpen = false }
                Button("Release All Inputs") { GameInput.release() }
                Button {
                    GameInput.release()
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
                                GameInput.release()
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
                            onSelect: { editingStickID=stick.id; editingJoystick = true }, onMove: { point in
                let x=Double(point.x / max(1,size.width)), y=Double(point.y / max(1,size.height))
                if profile.joystick?.id == stick.id { profile.joystick?.x=x; profile.joystick?.y=y }
                else if let index=profile.additionalJoysticks?.firstIndex(where:{$0.id == stick.id}) { profile.additionalJoysticks?[index].x=x; profile.additionalJoysticks?[index].y=y }
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
            KeySurface(title: button.label, key: button.key, configuration: button, highContrast: profile.highContrast == true, haptics: profile.haptics == true)
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
        syncMouseMode()
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
                TextField("Custom key name",text:$button.key).autocapitalization(.none).disableAutocorrection(true)
                Picker("Behavior", selection: Binding(get: { button.behavior ?? "hold" }, set: { button.behavior = $0 == "hold" ? nil : $0 })) {
                    Text("Hold while touched").tag("hold"); Text("Tap to toggle").tag("toggle"); Text("Repeat while touched").tag("repeat")
                }
                TextField("Additional keys, comma-separated", text: Binding(get: { button.combo?.joined(separator: ",") ?? "" }, set: { value in button.combo = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                Text("Examples: Shift,W or Control,S. Toggle holds until tapped again; Release All Inputs always clears it.").font(.caption)
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

