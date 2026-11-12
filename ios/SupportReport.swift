import Foundation
import UIKit

enum SupportReport {
    static func export(game: Game, library: GameLibrary) throws -> URL {
        var diagnostics: [String] = []
        let log = library.saveURL(game).appendingPathComponent("player.log")
        if let input = try? FileHandle(forReadingFrom: log) {
            defer { try? input.close() }
            let length = try input.seekToEnd(); try input.seek(toOffset: length > 32768 ? length - 32768 : 0)
            let text = String(decoding: try input.read(upToCount: 32768) ?? Data(), as: UTF8.self)
            diagnostics = text.components(separatedBy: .newlines).filter { line in
                ["ERROR", "WARNING", "SCRIPT ERROR", "Godot Player:", "Godot Engine", "OpenGL", "Metal"].contains { line.contains($0) }
            }.suffix(200).map {
                $0.replacingOccurrences(of: library.saves.path, with: "<saves>")
                    .replacingOccurrences(of: library.root.path, with: "<library>")
                    .replacingOccurrences(of: NSHomeDirectory(), with: "<app>")
            }
        }
        let report: [String: Any] = [
            "schema": 1, "created": ISO8601DateFormatter().string(from: Date()),
            "app": "Godot Hollow Launcher", "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            "spineRuntime": Bundle.main.object(forInfoDictionaryKey: "HollowSpineRuntime") as? String ?? "unknown",
            "system": UIDevice.current.systemVersion, "deviceFamily": UIDevice.current.model,
            "engineMetadata": game.pack.version, "packFormat": game.pack.format,
            "compiledScripts": game.pack.scriptVersions ?? [], "nativeDescriptors": game.pack.nativeFiles ?? [],
            "runtimeOverride": game.runtime, "renderer": game.renderer, "orientation": game.displayOrientation,
            "importNote": game.importNote ?? "Original standalone PCK",
            "compatibility": RuntimeSelection.problem(for: game) ?? "Candidate; runtime execution required",
            "lastLaunchStatus": library.previousLaunch(game)?.status ?? "none", "diagnostics": diagnostics,
            "privacy": "No PCK, executable, save contents, library notes, or full log included. Review diagnostics before sharing."
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Hollow-support-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        return url
    }
}
