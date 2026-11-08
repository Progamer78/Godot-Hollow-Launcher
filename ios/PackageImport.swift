import Foundation
import CryptoKit

struct ArchiveEntry {
    let name: String
    let size: UInt64
    let directory: Bool
    let position: UInt64
    let index: UInt64
}

enum PackageImport {
    static let extensions = ["pck", "zip", "apk", "exe"]
    static func entries(_ url: URL) throws -> [ArchiveEntry] {
        try GPArchive.entries(at: url.path).map { value in
            guard let name = value["name"] as? String, let size = value["size"] as? NSNumber else { throw PackError.invalid("Malformed archive entry.") }
            guard let position = value["position"] as? NSNumber, let index = value["index"] as? NSNumber else { throw PackError.invalid("Missing archive position.") }
            return ArchiveEntry(name: name, size: size.uint64Value, directory: (value["directory"] as? NSNumber)?.boolValue ?? false, position: position.uint64Value, index: index.uint64Value)
        }
    }
    @discardableResult
    static func prepare(_ source: URL, destination: URL, engineHint: UInt32? = nil) throws -> String? {
        switch source.pathExtension.lowercased() {
        case "pck": try FileManager.default.copyItem(at: source, to: destination); return nil
        case "exe": try embedded(source, destination: destination); return "Original embedded PCK extracted; the executable was not run."
        case "apk", "zip":
            let files = try entries(source)
            let packs = files.filter { !$0.directory && ($0.name as NSString).pathExtension.lowercased() == "pck" && !$0.name.hasSuffix(".sparsepck") }
            if packs.count == 1 {
                try extract(source, entry: packs[0], destination: destination, limit: 16 << 30)
                return "Original PCK extracted from \(source.pathExtension.uppercased()). Desktop/Android native libraries are not imported."
            }
            if packs.count > 1 { throw PackError.invalid("This archive contains several PCKs: \(packs.prefix(6).map(\.name).joined(separator: ", ")). Extract and import the desired complete PCK.") }
            if files.contains(where: { $0.name.hasSuffix(".sparsepck") }) { throw PackError.invalid("This APK uses a sparse or encrypted asset layout. Import a complete standalone PCK; its required external data or export key is not available here.") }
            let assets = files.filter { !$0.directory && $0.name.hasPrefix("assets/") && $0.name != "assets/_cl_" }
            guard assets.contains(where: { ["assets/project.binary", "assets/project.godot"].contains($0.name) }) else {
                throw PackError.invalid("No complete Godot game found. Split APKs, asset-delivery downloads and non-Godot APKs are unsupported. Choose a standalone PCK or full Godot APK.")
            }
            try wrapAssets(source, assets: assets, destination: destination, engineHint: engineHint)
            let libraries = files.filter { $0.name.hasPrefix("lib/") && $0.name.hasSuffix(".so") && !$0.name.contains("libgodot") }.prefix(8).map(\.name)
            return "Original APK asset bytes wrapped in a standalone PCK. Header records the inferred engine family; exact original engine version is unknown. Android plugins and platform-specific textures may prevent execution." + (libraries.isEmpty ? "" : " Ignored Android libraries: \(libraries.joined(separator: ", ")).")
        default: throw PackError.invalid("Choose a PCK, ZIP, Godot APK, or executable containing an embedded PCK.")
        }
    }
    static func extract(_ archive: URL, entry: ArchiveEntry, destination: URL, limit: UInt64) throws {
        try GPArchive.extract(archive.path, entry: entry.name, destination: destination.path, limit: limit, position: entry.position, index: entry.index)
    }
    static func copy(_ input: FileHandle, to output: FileHandle, bytes: UInt64) throws {
        var remaining = bytes
        while remaining > 0 {
            let data = try input.read(upToCount: Int(min(remaining, 1024 * 1024))) ?? Data()
            guard !data.isEmpty else { throw PackError.invalid("Truncated game data.") }
            try output.write(contentsOf: data); remaining -= UInt64(data.count)
        }
    }
    private static func embedded(_ source: URL, destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let length = try input.seekToEnd()
        guard length >= 16 else { throw PackError.invalid("No embedded PCK footer found.") }
        try input.seek(toOffset: length - 12)
        let footer = try input.read(upToCount: 12) ?? Data()
        guard footer.count == 12, footer.suffix(4) == Data("GDPC".utf8) else { throw PackError.invalid("This executable has no supported embedded PCK footer. The executable will not be run.") }
        let size = footer.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        guard size >= 84, size <= length - 12 else { throw PackError.invalid("Invalid embedded PCK size.") }
        try input.seek(toOffset: length - 12 - size)
        guard try input.read(upToCount: 4) == Data("GDPC".utf8) else { throw PackError.invalid("Embedded PCK header not found.") }
        try input.seek(toOffset: length - 12 - size)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        try copy(input, to: output, bytes: size)
        // Older exports may use executable-absolute asset offsets. Validation
        // rejects those instead of silently changing an original pack.
    }
    private static func integer<T: FixedWidthInteger>(_ number: T) -> Data {
        var value = number.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private static func wrapAssets(_ source: URL, assets: [ArchiveEntry], destination: URL, engineHint: UInt32?) throws {
        let temp = destination.deletingLastPathComponent().appendingPathComponent("asset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        var major = engineHint
        if major == nil, assets.contains(where: { $0.name.hasPrefix("assets/.godot/") }) { major = 4 }
        if major == nil, let script = assets.first(where: { $0.name.hasSuffix(".gdc") && $0.size >= 12 && $0.size <= 16 * 1024 * 1024 }) {
            try extract(source, entry: script, destination: temp, limit: 16 * 1024 * 1024)
            let file = try FileHandle(forReadingFrom: temp); let prefix = try file.read(upToCount: 8) ?? Data(); try file.close()
            if prefix.count == 8 && prefix.prefix(4) == Data("GDSC".utf8) {
                let version = prefix.suffix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
                major = version >= 100 ? 4 : 3
            }
        }
        if major == nil, let project = assets.first(where: { $0.name == "assets/project.godot" && $0.size <= 1024 * 1024 }) {
            try extract(source, entry: project, destination: temp, limit: 1024 * 1024)
            let text = try String(contentsOf: temp, encoding: .utf8)
            if text.contains("config_version=5") { major = 4 }
            else if text.contains("config_version=4") { major = 3 }
        }
        guard let engine = major, [3, 4].contains(engine) else { throw PackError.invalid("Could not identify this APK's Godot engine family. Choose Godot 3 or 4 under APK engine hint in the library, then import again.") }
        let format: UInt32 = engine == 3 ? 1 : 2
        let header = engine == 3 ? 84 : 96
        let directorySize = assets.reduce(4) { $0 + 4 + 6 + $1.name.dropFirst(7).utf8.count + (engine == 3 ? 32 : 36) }
        guard directorySize <= 64 * 1024 * 1024 else { throw PackError.invalid("APK asset directory is too large.") }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        var prefix = Data("GDPC".utf8) + integer(format) + integer(engine) + integer(UInt32(0)) + integer(UInt32(0))
        prefix += Data(repeating: 0, count: header - prefix.count)
        try output.write(contentsOf: prefix + integer(UInt32(assets.count)))
        var payloadOffset = UInt64(header + directorySize)
        var checksums: [UInt64] = []
        for asset in assets {
            // Godot 3 hashes the complete res:// path; Godot 4 normalizes it.
            let name = Data(("res://" + asset.name.dropFirst(7)).utf8)
            try output.write(contentsOf: integer(UInt32(name.count)) + name + integer(payloadOffset) + integer(asset.size))
            checksums.append(try output.offset())
            try output.write(contentsOf: Data(repeating: 0, count: 16 + (engine == 3 ? 0 : 4)))
            payloadOffset += asset.size
        }
        for (index, asset) in assets.enumerated() {
            try extract(source, entry: asset, destination: temp, limit: 16 << 30)
            let input = try FileHandle(forReadingFrom: temp); defer { try? input.close() }
            var digest = Insecure.MD5()
            while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                digest.update(data: bytes); try output.write(contentsOf: bytes)
            }
            let end = try output.offset(); try output.seek(toOffset: checksums[index])
            try output.write(contentsOf: Data(digest.finalize())); try output.seek(toOffset: end)
            try input.close(); try FileManager.default.removeItem(at: temp)
        }
    }
}
