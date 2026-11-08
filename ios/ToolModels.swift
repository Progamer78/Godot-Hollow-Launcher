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
    var id: String { object + ":" + path.map { "\($0.kind):\($0.name ?? ""):\($0.index ?? -1)" }.joined(separator: "/") }
}

struct ToolReply: Decodable {
    let ok: Bool
    let message: String?
    let rows: [ToolStat]?
    let truncated: Bool?
    let visited: Int?
    let undoCount: Int?
}
