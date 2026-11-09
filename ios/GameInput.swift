import Foundation

enum GameInput {
    static let padNames = ["Pad A", "Pad B", "Pad X", "Pad Y", "Pad L1", "Pad R1", "Pad Select", "Pad Start", "Pad L3", "Pad R3", "Pad Up", "Pad Down", "Pad Left", "Pad Right"]
    private static var padHolds: [String: Int] = [:]
    private static var keyCounts: [String: Int] = [:]
    static var outputDevice: Int?
    static func ordered(_ keys: Set<String>) -> [String] {
        let modifiers=["Shift","Control","Alt","Meta"]
        return keys.sorted {
            let left=modifiers.firstIndex(of:$0) ?? 100, right=modifiers.firstIndex(of:$1) ?? 100
            return left == right ? $0 < $1 : left < right
        }
    }
    private static func send(_ command: [String:Any]) {
        var value=command
        if let device=outputDevice { value["device"]=device }
        _ = ToolsBridge.send(value)
    }
    static var debugKeys: Set<String> { Set(keyCounts.filter { $0.value > 0 }.map { $0.key }) }
    static var axes: [Int: Double] = [:]
    private static var axisSources: [Int: [String:Double]] = [:]
    static func key(_ name: String, pressed: Bool) {
        keyCounts[name] = max(0, (keyCounts[name] ?? 0) + (pressed ? 1 : -1))
        if let button = padNames.firstIndex(of: name) {
            let old = padHolds[name] ?? 0, next = max(0, old + (pressed ? 1 : -1)); padHolds[name] = next
            if (old == 0) != (next == 0) { send(["action": "input", "kind": "button", "button": button, "pressed": next > 0]) }
        } else if name == "Pad L2" || name == "Pad R2" {
            axis(name == "Pad L2" ? 4 : 5, value: (keyCounts[name] ?? 0) > 0 ? 1 : 0)
        } else { PlayerRuntime.setKey(name, pressed: pressed) }
    }
    static func axis(_ axis: Int, value: Double, source: String = "legacy") {
        let checked = value.isFinite ? min(1, max(-1, value)) : 0
        if checked == 0 { axisSources[axis]?[source]=nil } else { axisSources[axis,default:[:]][source]=checked }
        let resolved=min(1,max(-1,(axisSources[axis] ?? [:]).values.reduce(0,+)))
        axes[axis] = resolved
        send(["action": "input", "kind": "axis", "axis": axis, "value": resolved])
    }
    static func release() {
        if outputDevice != nil {
            for (index,name) in padNames.enumerated() where (padHolds[name] ?? 0)>0 { send(["action":"input","kind":"button","button":index,"pressed":false]) }
            for axis in axes.keys { send(["action":"input","kind":"axis","axis":axis,"value":0]) }
        }
        PlayerRuntime.releaseKeys()
        _ = ToolsBridge.send(["action": "release_input"])
        padHolds.removeAll(); keyCounts.removeAll(); axes.removeAll(); axisSources.removeAll()
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
