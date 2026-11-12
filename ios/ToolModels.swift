import Foundation

struct ToolPathStep: Codable, Equatable {
    let kind: String
    let name: String?
    let index: Int?
}

struct ToolStat: Codable, Identifiable, Equatable {
    let object: String // Keep full 64-bit instance IDs out of floating-point JSON numbers.
    let path: [ToolPathStep]
    let label: String
    let type: String
    let value: String
    var frozen: Bool? = nil
    var id: String { object + ":" + path.map { "\($0.kind):\($0.name ?? ""):\($0.index ?? -1)" }.joined(separator: "/") }
}

struct ToolReply: Decodable {
    let ok: Bool
    let message: String?
    let rows: [ToolStat]?
    let truncated: Bool?
    let visited: Int?
    let undoCount: Int?
    var ready: Bool? = nil
    var fps: Double? = nil
    var frameMs: Double? = nil
    var processMs: Double? = nil
    var physicsMs: Double? = nil
    var engineMemoryBytes: Double? = nil
}

struct SavedCheat: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var label: String
    var type: String
    var value: String
    var monitored: Bool?
    var editorValue: String {
        get { type == "bool" ? value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : value }
        set { value = newValue }
    }
    // A stable scene/resource label is resolved again each session. Instance
    // IDs are deliberately not persisted across process lifetimes.
}

struct PinnedReadout: Identifiable {
    let id: UUID
    let name: String
    let value: String
    var frozen = false
}
