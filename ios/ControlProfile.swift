import Foundation

struct ControlButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var key: String
    // Fractions of the available control area survive rotation and resizing.
    var x: Double
    var y: Double
    var width: Double = 68
    var height: Double = 52

    mutating func constrain() {
        x = x.isFinite ? min(1, max(0, x)) : 0.5
        y = y.isFinite ? min(1, max(0, y)) : 0.5
        width = width.isFinite ? min(160, max(44, width)) : 68
        height = height.isFinite ? min(120, max(44, height)) : 52
    }
}

struct ControlProfile: Codable, Equatable {
    var buttons: [ControlButton]
    var mouseEnabled = false
    var mouseMode = "trackpad"
    var mouseSensitivity = 1.0

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
        var identities = Set<UUID>()
        buttons = Array(buttons.filter { identities.insert($0.id).inserted }.prefix(32))
        for index in buttons.indices { buttons[index].constrain() }
        mouseSensitivity = mouseSensitivity.isFinite ? min(3, max(0.25, mouseSensitivity)) : 1
        if !["trackpad", "direct"].contains(mouseMode) { mouseMode = "trackpad" }
    }
}

enum ControlKeys {
    static let all: [String] = {
        var keys = ["Up", "Down", "Left", "Right", "Enter", "Escape", "Space", "Tab", "Shift", "Control", "Alt", "Meta", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown"]
        keys += (65...90).map { String(UnicodeScalar($0)!) }
        keys += (0...9).map { String($0) }
        keys += (1...12).map { "F\($0)" }
        keys += ["-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`", "Mouse Left", "Mouse Right", "Mouse Middle"]
        return keys
    }()
}
