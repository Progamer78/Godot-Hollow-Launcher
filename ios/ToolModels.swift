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
    var previous: String? = nil
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
    var searching: Bool? = nil
    var searchDiscovery: Bool? = nil
    var searchTypes: [String]? = nil
    var examined: Int? = nil
    var workingMatches: Int? = nil
    var page: Int? = nil
    var pageCount: Int? = nil
    var searchStarted: Bool? = nil
    var searchKind: String? = nil
    var searchFilter: String? = nil
    var searchScope: String? = nil
    var candidateCount: Int? = nil
    var staleCount: Int? = nil
    var searchSteps: Int? = nil
    var searchUndoCount: Int? = nil
    var nodes: [ToolSceneNode]? = nil
    var currentScene: ToolSceneNode? = nil
    var node: ToolSceneNode? = nil
    var actions: [ToolSceneAction]? = nil
    var scriptSource: String? = nil
    var sourceTruncated: Bool? = nil
    var snapshotCount: Int? = nil
    var changedCount: Int? = nil
}

struct ToolSceneNode: Decodable, Identifiable, Equatable {
    let object: String
    let name: String
    let path: String
    let className: String
    let scriptPath: String
    let scenePath: String
    let visible: Bool?
    let processing: Bool
    let inputProcessing: Bool
    var id: String { object }
}

struct ToolSceneAction: Decodable {
    let signal: String
    let method: String
    let targetPath: String
    let targetObject: String
}

struct SavedCheat: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var label: String
    var type: String
    var value: String
    var monitored: Bool?
    static func defaultName(for label: String) -> String {
        let last = label.split(whereSeparator: { $0 == "." || $0 == "/" }).last.map(String.init) ?? label
        return String(last.prefix(80))
    }
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == label ? Self.defaultName(for: label) : trimmed
    }
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
