import Foundation

struct JoystickControl: Codable, Equatable, Identifiable {
    var identifier: UUID?
    var zone: String?
    var id: UUID { identifier ?? UUID(uuidString:"00000000-0000-0000-0000-000000000001")! }
    var mode = "fixed"
    var x = 0.2
    var y = 0.76
    var diameter = 128.0
    var deadzone = 0.18
    var up = "Up"
    var down = "Down"
    var left = "Left"
    var right = "Right"
    var output: String?
    var axis: Int?

    func analog(dx: Double, dy: Double) -> (Double, Double) {
        guard dx.isFinite, dy.isFinite else { return (0, 0) }
        let length = hypot(dx, dy)
        guard length > deadzone else { return (0, 0) }
        let strength = min(1, (length - deadzone) / (1 - deadzone))
        return (dx / length * strength, dy / length * strength)
    }

    mutating func constrain() {
        if !["fixed", "floating"].contains(mode) { mode = "fixed" }
        if output != "gamepad" { output = nil }
        // nil is the persisted legacy/default left stick. Keep it unset so
        // saving an otherwise valid layout does not change its identity.
        if let selectedAxis = axis, ![0, 2].contains(selectedAxis) { axis = 0 }
        x = x.isFinite ? min(1, max(0, x)) : 0.2
        y = y.isFinite ? min(1, max(0, y)) : 0.76
        diameter = diameter.isFinite ? min(220, max(90, diameter)) : 128
        deadzone = deadzone.isFinite ? min(0.5, max(0.08, deadzone)) : 0.18
        if let zone=zone, !["full","left","right"].contains(zone) { self.zone=nil }
        up=String(up.trimmingCharacters(in:.whitespacesAndNewlines).prefix(32)); if up.isEmpty { up="Up" }
        down=String(down.trimmingCharacters(in:.whitespacesAndNewlines).prefix(32)); if down.isEmpty { down="Down" }
        left=String(left.trimmingCharacters(in:.whitespacesAndNewlines).prefix(32)); if left.isEmpty { left="Left" }
        right=String(right.trimmingCharacters(in:.whitespacesAndNewlines).prefix(32)); if right.isEmpty { right="Right" }
    }

    // Values are relative to the stick radius. A radial deadzone prevents
    // jitter, while angular thresholds allow both cardinal and diagonal input.
    func keys(dx: Double, dy: Double) -> Set<String> {
        guard dx.isFinite, dy.isFinite else { return [] }
        let length = hypot(dx, dy)
        guard length > deadzone else { return [] }
        var result = Set<String>()
        if dx / length < -0.38 { result.insert(left) }
        if dx / length > 0.38 { result.insert(right) }
        if dy / length < -0.38 { result.insert(up) }
        if dy / length > 0.38 { result.insert(down) }
        return result
    }
}

enum GameViewport {
    static func frame(width: Double, height: Double, aspect: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return (0, 0, 0, 0) }
        guard height > width else { return (0, 0, width, height) }
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 16.0 / 9.0
        let w = min(width, height * ratio), h = min(height, width / ratio)
        return ((width - w) / 2, (height - h) / 2, w, h)
    }
}

struct ControlButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var key: String
    // Fractions of the available control area survive rotation and resizing.
    var x: Double
    var y: Double
    var width: Double = 68
    var height: Double = 52
    var behavior: String?
    var combo: [String]?

    mutating func constrain() {
        x = x.isFinite ? min(1, max(0, x)) : 0.5
        y = y.isFinite ? min(1, max(0, y)) : 0.5
        width = width.isFinite ? min(160, max(44, width)) : 68
        height = height.isFinite ? min(120, max(44, height)) : 52
        label = String(label.prefix(24))
        key = String(key.prefix(32))
        if key.isEmpty { key = "Space" }
        if !["toggle", "repeat"].contains(behavior ?? "") { behavior = nil }
        if let keys = combo { combo = Array(Set(keys.map { String($0.trimmingCharacters(in: .whitespaces).prefix(32)) }.filter { !$0.isEmpty })).sorted().prefix(4).map { $0 } }
    }
}

struct ControlProfile: Codable, Equatable {
    var buttons: [ControlButton]
    var mouseEnabled = false
    var mouseMode = "trackpad"
    var mouseSensitivity = 1.0
    var joystick: JoystickControl?
    var additionalJoysticks: [JoystickControl]?
    var controller: ControllerProfile?
    var gestures: TouchGestures?
    var sticks: [JoystickControl] { (joystick.map { [$0] } ?? []) + (additionalJoysticks ?? []) }
    var opacity: Double?
    var highContrast: Bool?
    var haptics: Bool?

    static let presetNames = ["Platformer", "RPG - WASD", "Analog gamepad", "Visual novel", "Mouse / trackpad"]
    static func preset(_ name: String) -> ControlProfile {
        var value = legacy(directions: name == "RPG - WASD" ? "wasd" : "arrows", extras: "Space,Shift")
        if name == "Analog gamepad" {
            var stick = JoystickControl(); stick.output = "gamepad"; value.joystick = stick
            value.buttons = [ControlButton(label: "A", key: "Pad A", x: 0.86, y: 0.85), ControlButton(label: "B", key: "Pad B", x: 0.95, y: 0.65), ControlButton(label: "Start", key: "Pad Start", x: 0.6, y: 0.9)]
        } else if name == "Visual novel" {
            value.buttons = [ControlButton(label: "Next", key: "Enter", x: 0.9, y: 0.85), ControlButton(label: "Menu", key: "Escape", x: 0.1, y: 0.85), ControlButton(label: "Skip", key: "Control", x: 0.1, y: 0.65, behavior: "toggle")]
        } else if name == "Mouse / trackpad" {
            value.mouseEnabled = true
            value.buttons = [ControlButton(label: "Left", key: "Mouse Left", x: 0.82, y: 0.86), ControlButton(label: "Right", key: "Mouse Right", x: 0.95, y: 0.86), ControlButton(label: "Back", key: "Escape", x: 0.1, y: 0.86)]
        }
        return value
    }

    static func legacy(directions: String, extras: String, areaWidth: Double = 700, areaHeight: Double = 300) -> ControlProfile {
        let keys = directions == "wasd" ? ["W", "A", "S", "D"] : ["Up", "Left", "Down", "Right"]
        var buttons = [
            ControlButton(label: "↑", key: keys[0], x: 0.14, y: 0.68),
            ControlButton(label: "←", key: keys[1], x: 0.05, y: 0.88),
            ControlButton(label: "↓", key: keys[2], x: 0.14, y: 0.88),
            ControlButton(label: "→", key: keys[3], x: 0.23, y: 0.88),
            ControlButton(label: "Cancel", key: "Escape", x: 0.76, y: 0.88),
            ControlButton(label: "Confirm", key: "Enter", x: 0.91, y: 0.88)
        ]
        let additional = Array(Set(extras.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })).sorted().prefix(6)
        for (index, key) in additional.enumerated() where !key.isEmpty {
            buttons.append(ControlButton(label: key, key: key, x: 0.94 - Double(index % 3) * 0.13, y: index < 3 ? 0.64 : 0.43))
        }
        // Start with a compact, non-overlapping pad on either phone orientation.
        // The game view supplies its actual safe-area canvas before first use.
        let width = max(1, areaWidth), height = max(1, areaHeight)
        let padX = 84.0, bottom = max(26, height - 30)
        let points = [(padX, bottom - 58), (padX - 58, bottom), (padX, bottom), (padX + 58, bottom),
                      (width - 116, bottom), (width - 36, bottom)]
        for index in buttons.indices {
            let point = index < 6 ? points[index] : (width - 36 - Double((index - 6) % 3) * 78, bottom - 66 - Double((index - 6) / 3) * 60)
            buttons[index].x = point.0 / width
            buttons[index].y = point.1 / height
            if index < 4 { buttons[index].width = 52 }
            buttons[index].constrain()
        }
        return ControlProfile(buttons: buttons)
    }

    mutating func constrain() {
        var buttonIDs = Set<UUID>()
        buttons = Array(buttons.filter { buttonIDs.insert($0.id).inserted }.prefix(32))
        for index in buttons.indices { buttons[index].constrain() }
        mouseSensitivity = mouseSensitivity.isFinite ? min(3, max(0.25, mouseSensitivity)) : 1
        if !["trackpad", "direct"].contains(mouseMode) { mouseMode = "trackpad" }
        joystick?.constrain()
        var stickIDs = Set<UUID>()
        if let first = joystick { stickIDs.insert(first.id) }
        additionalJoysticks = additionalJoysticks.map { values in
            Array(values.filter { stickIDs.insert($0.id).inserted }.prefix(3)).map { value in
                var stick = value
                stick.constrain()
                return stick
            }
        }
        if sticks.contains(where: { $0.mode == "floating" }) { mouseEnabled = false }
        controller?.constrain()
        gestures?.constrain()
        if let opacity = opacity { self.opacity = opacity.isFinite ? min(1, max(0.2, opacity)) : 0.7 }
    }
}

struct TouchGestures: Codable, Equatable {
    var enabled=false
    var twoFingerTap="Mouse Right"
    var threeFingerTap="Escape"
    var scroll=true
    mutating func constrain() {
        twoFingerTap=String(twoFingerTap.prefix(32)); threeFingerTap=String(threeFingerTap.prefix(32))
    }
}

enum ControlKeys {
    static let all: [String] = {
        var keys = ["Up", "Down", "Left", "Right", "Enter", "Escape", "Space", "Tab", "Shift", "Control", "Alt", "Meta", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown"]
        keys += (65...90).map { String(UnicodeScalar($0)!) }
        keys += (0...9).map { String($0) }
        keys += (1...12).map { "F\($0)" }
        keys += ["-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`", "Mouse Left", "Mouse Right", "Mouse Middle"]
        keys += ["Pad A", "Pad B", "Pad X", "Pad Y", "Pad L1", "Pad R1", "Pad Select", "Pad Start", "Pad L3", "Pad R3", "Pad Up", "Pad Down", "Pad Left", "Pad Right", "Pad L2", "Pad R2"]
        return keys
    }()
}
