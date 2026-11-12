import Foundation

struct PinnedMonitorState {
    private var targets: [UUID: ToolStat] = [:]
    private var cursor = 0
    mutating func poll(_ pins: [SavedCheat]) -> [PinnedReadout] {
        let pins = Array(pins.filter { $0.monitored == true }.prefix(5))
        let identities = Set(pins.map(\.id))
        targets = targets.filter { identities.contains($0.key) }
        let unresolved = pins.filter { targets[$0.id] == nil }
        let lookup = unresolved.isEmpty ? nil : unresolved[cursor % unresolved.count].id
        if !unresolved.isEmpty { cursor = (cursor + 1) % 1000 }
        return pins.map { pin in
            var value = "Looking up…"
            var frozen = false
            if let target = targets[pin.id], let encoded = ToolsBridge.target(target) {
                let reply = ToolsBridge.send(["action": "read", "target": encoded])
                if reply.ok, let updated = reply.rows?.first { value = updated.value; frozen = updated.frozen == true }
                else { targets[pin.id] = nil; value = "Unavailable" }
            } else if lookup == pin.id {
                let matches = (ToolsBridge.send(["action": "scan", "search": pin.label]).rows ?? []).filter { $0.label == pin.label && $0.type == pin.type }
                if matches.count == 1 { targets[pin.id] = matches[0]; value = matches[0].value; frozen = matches[0].frozen == true }
                else { value = matches.isEmpty ? "Unavailable" : "Ambiguous" }
            }
            return PinnedReadout(id: pin.id, name: pin.displayName, value: value, frozen: frozen)
        }
    }
}
