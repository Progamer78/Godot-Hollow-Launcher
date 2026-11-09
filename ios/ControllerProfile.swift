import Foundation

struct ControllerProfile: Codable, Equatable {
    var enabled = false
    var bindings: [String: String] = [:]
    var leftMode = "gamepad"
    var rightMode = "gamepad"
    var deadzone = 0.18
    var mouseSpeed = 700.0
    static let defaults = ["A":"Pad A", "B":"Pad B", "X":"Pad X", "Y":"Pad Y", "L1":"Pad L1", "R1":"Pad R1", "L2":"Pad L2", "R2":"Pad R2", "Menu":"Pad Start", "Options":"Pad Select", "L3":"Pad L3", "R3":"Pad R3", "Up":"Pad Up", "Down":"Pad Down", "Left":"Pad Left", "Right":"Pad Right", "Left Stick Up":"W", "Left Stick Down":"S", "Left Stick Left":"A", "Left Stick Right":"D", "Right Stick Up":"Up", "Right Stick Down":"Down", "Right Stick Left":"Left", "Right Stick Right":"Right"]
    var mouseEnabled: Bool { enabled && (leftMode == "mouse" || rightMode == "mouse") }
    func target(_ name: String) -> String { bindings[name] ?? Self.defaults[name] ?? "None" }
    mutating func constrain() {
        if !["gamepad", "keys", "mouse", "off"].contains(leftMode) { leftMode = "gamepad" }
        if !["gamepad", "keys", "mouse", "off"].contains(rightMode) { rightMode = "gamepad" }
        deadzone = deadzone.isFinite ? min(0.6, max(0.05, deadzone)) : 0.18
        mouseSpeed = mouseSpeed.isFinite ? min(2000, max(100, mouseSpeed)) : 700
        var checked: [String:String] = [:]
        for (name,target) in bindings.sorted(by: { $0.key < $1.key }).prefix(96) {
            let trimmed=String(target.trimmingCharacters(in: .whitespaces).prefix(32))
            checked[String(name.prefix(160))] = trimmed.isEmpty ? "None" : trimmed
        }
        bindings=checked
    }
    func stick(_ x: Double, _ y: Double) -> (Double, Double) {
        guard x.isFinite, y.isFinite else { return (0,0) }
        let length = hypot(x,y)
        guard length > deadzone else { return (0,0) }
        let strength = min(1, (length-deadzone)/(1-deadzone))
        return (x/length*strength,y/length*strength)
    }
}
