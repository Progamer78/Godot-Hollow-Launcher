import Foundation

enum GameInput {
    static let padNames = ["Pad A", "Pad B", "Pad X", "Pad Y", "Pad L1", "Pad R1", "Pad Select", "Pad Start", "Pad L3", "Pad R3", "Pad Up", "Pad Down", "Pad Left", "Pad Right"]
    private static var padHolds: [String: Int] = [:]
    private static var keyCounts: [String: Int] = [:]
    static var debugKeys: Set<String> { Set(keyCounts.filter { $0.value > 0 }.map { $0.key }) }
    static var axes: [Int: Double] = [:]
    static func key(_ name: String, pressed: Bool) {
        keyCounts[name] = max(0, (keyCounts[name] ?? 0) + (pressed ? 1 : -1))
        if let button = padNames.firstIndex(of: name) {
            let old = padHolds[name] ?? 0, next = max(0, old + (pressed ? 1 : -1)); padHolds[name] = next
            if (old == 0) != (next == 0) { _ = ToolsBridge.send(["action": "input", "kind": "button", "button": button, "pressed": next > 0]) }
        } else if name == "Pad L2" || name == "Pad R2" {
            axis(name == "Pad L2" ? 4 : 5, value: (keyCounts[name] ?? 0) > 0 ? 1 : 0)
        } else { PlayerRuntime.setKey(name, pressed: pressed) }
    }
    static func axis(_ axis: Int, value: Double) {
        let checked = value.isFinite ? min(1, max(-1, value)) : 0
        axes[axis] = checked
        _ = ToolsBridge.send(["action": "input", "kind": "axis", "axis": axis, "value": checked])
    }
    static func release() {
        PlayerRuntime.releaseKeys()
        _ = ToolsBridge.send(["action": "release_input"])
        padHolds.removeAll(); keyCounts.removeAll(); axes.removeAll()
        NotificationCenter.default.post(name: Notification.Name("GodotPlayerReleaseInputs"), object: nil)
    }

    @discardableResult
    static func text(_ text: String) -> Bool {
        // Bound each native request in Unicode scalars (including on Godot 3's
        // UTF-16 builds). Paste uses the same input path as ordinary typing.
        var chunk = "", count = 0
        for scalar in text.unicodeScalars {
            chunk.unicodeScalars.append(scalar); count += 1
            if count == 512 {
                guard ToolsBridge.send(["action": "input", "kind": "text", "text": chunk]).ok else { return false }
                chunk = ""; count = 0
            }
        }
        return chunk.isEmpty || ToolsBridge.send(["action": "input", "kind": "text", "text": chunk]).ok
    }
}
