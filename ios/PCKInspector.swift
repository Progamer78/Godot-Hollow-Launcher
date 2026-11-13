import Foundation

struct PackInfo: Codable, Equatable {
    let format: UInt32
    let major: UInt32
    let minor: UInt32
    let patch: UInt32
    let fileCount: UInt32
    let byteCount: UInt64
    var nativeFiles: [String]?
    var scriptVersions: [UInt32]?
    var encryptedScriptCount: Int?
    var encryptedFileCount: Int? = nil
    var encryptedDirectory: Bool? = nil
    var needsKey: Bool { (encryptedScriptCount ?? 0) > 0 || (encryptedFileCount ?? 0) > 0 || encryptedDirectory == true }
    var version: String { "\(major).\(minor).\(patch)" }
}

enum PackError: LocalizedError {
    case invalid(String)
    case encryptedScripts(major: UInt32, count: Int, example: String)
    case encryptedPack(major: UInt32)
    case unsupportedRuntime(String)
    var recoveryMajor: UInt32? {
        switch self {
        case .encryptedScripts(let major, _, _), .encryptedPack(let major): return [3, 4].contains(major) ? major : nil
        default: return nil
        }
    }
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .unsupportedRuntime(let reason): return reason
        case .encryptedPack(let major):
            return "This Godot \(major) pack has an encrypted directory or assets. Select its original Windows x64 EXE together with the PCK, or import a ZIP containing both, to try export key recovery."
        case .encryptedScripts(let major, let count, let example):
            let recovery = major == 3
                ? "Select its original Godot 3 Windows x64 EXE together with the PCK, or import a ZIP containing both, to try automatic export encryption key recovery. Other encryption layouts require an unencrypted export."
                : "Select its original Godot 4 Windows x64 EXE together with the PCK, or import a ZIP containing both, to try export encryption key recovery. Unrecognized layouts need an unencrypted export."
            return "This Godot \(major) pack contains \(count) encrypted scripts, including \(example). \(recovery)"
        }
    }
}

// Implements PackedSourcePCK::try_open_pack in the pinned official engine.
// Inspect only the header and directory; game assets are never extracted.
enum PCKInspector {
    static func inspect(_ url: URL, decryptScript: ((Data) throws -> Data)? = nil, decryptBlock: ((Data, Bool) throws -> Data)? = nil) throws -> PackInfo {
        let file = try PackReader(url)
        var reader = file
        let packSize = file.size
        guard try reader.u32() == 0x43504447 else { throw PackError.invalid("Not a standalone Godot PCK (GDPC header missing).") }
        let format = try reader.u32()
        let major = try reader.u32(), minor = try reader.u32(), patch = try reader.u32()
        guard (1...4).contains(format) else { throw PackError.invalid("Unsupported pack format \(format).") }
        let headerSize: UInt64 = format == 1 ? 84 : (format == 2 ? 96 : 104)
        var flags: UInt32 = 0, base: UInt64 = 0
        if format >= 2 {
            flags = try reader.u32()
            guard flags & ~UInt32(7) == 0 else { throw PackError.invalid("Unknown PCK header flags.") }
            guard flags & 4 == 0 else { throw PackError.invalid("Sparse packs require external files; import a complete standalone pack.") }
            if flags & 1 != 0 && (major != 4 || decryptBlock == nil) { throw PackError.encryptedPack(major: major) }
            base = try reader.u64()
        }
        if format >= 3 {
            let directoryOffset = try reader.u64()
            guard directoryOffset >= headerSize else { throw PackError.invalid("PCK directory overlaps the header.") }
            try reader.seek(directoryOffset)
        } else {
            try reader.seek(reader.position + 64)
        }
        let directoryStart = reader.position
        let count = try reader.u32()
        var encryptedDirectoryEnd: UInt64?
        if flags & 1 != 0, let decrypt = decryptBlock {
            let bytes = try file.encryptedBlock(magic: false, limit: 64 * 1024 * 1024)
            encryptedDirectoryEnd = file.position
            reader = PackReader(data: try decrypt(bytes, false))
        }
        guard count > 0, count <= 1_000_000, UInt64(count) <= (reader.size - reader.position) / 36 else {
            throw PackError.invalid("Invalid or oversized PCK directory.")
        }
        var names = Set<String>(), hasProject = false
        var binarySettings: PackAsset?
        var ranges: [(UInt64, UInt64)] = []
        var nativeFiles: [String] = []
        var encryptedScripts = 0
        var encryptedEntries: [PackAsset] = []
        var encryptedExample = ""
        var compiledScripts: [PackAsset] = []
        var encryptedFiles: [PackAsset] = []
        var dotnetExample: String?
        for _ in 0..<count {
            let length = try reader.u32()
            guard length > 0, length <= 16_384 else { throw PackError.invalid("Invalid PCK path length.") }
            var bytes = try reader.read(Int(length))
            while bytes.last == 0 { bytes.removeLast() }
            guard let raw = String(data: bytes, encoding: .utf8), !raw.contains("\0") else { throw PackError.invalid("Invalid UTF-8 PCK path.") }
            let path = raw.hasPrefix("res://") ? String(raw.dropFirst(6)) : raw
            guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
                  names.insert(path).inserted else { throw PackError.invalid("Unsafe or duplicate PCK path: \(raw)") }
            let offset = try reader.u64(), size = try reader.u64()
            _ = try reader.read(16) // MD5 belongs to the asset, not the directory.
            let fileFlags = format >= 2 ? try reader.u32() : 0
            guard fileFlags & ~UInt32(1) == 0 else { throw PackError.invalid("Removal, delta, or unknown entries are unsupported; this may be a patch pack.") }
            let encrypted = fileFlags & 1 != 0
            if encrypted && (major != 4 || decryptBlock == nil) { throw PackError.encryptedPack(major: major) }
            guard base <= packSize, offset <= packSize - base, size <= packSize - base - offset else {
                throw PackError.invalid("PCK asset lies outside the file: \(path)")
            }
            let asset = PackAsset(offset: base + offset, size: size, path: path, encrypted: encrypted)
            let storedSize = encrypted ? 40 + ((size + 15) & ~UInt64(15)) : size
            guard storedSize <= packSize - asset.offset else { throw PackError.invalid("Encrypted PCK asset lies outside the file: \(path)") }
            if storedSize > 0 { ranges.append((asset.offset, asset.offset + storedSize)) }
            if encrypted { encryptedFiles.append(asset) }
            hasProject = hasProject || path == "project.binary" || path == "project.godot"
            if path == "project.binary" { binarySettings = asset }
            if path == "project.godot", size == 0 { throw PackError.invalid("Empty project settings file.") }
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "gde" {
                encryptedScripts += 1
                encryptedEntries.append(asset)
                if encryptedExample.isEmpty || encryptedExample.hasPrefix("addons/") { encryptedExample = path }
            }
            if ext == "cs" || path.hasPrefix(".godot/mono/publish/") { dotnetExample = dotnetExample ?? path }
            if ext == "gdc" { compiledScripts.append(asset) }
            if ["gdextension", "gdnlib", "dll", "so", "dylib"].contains(ext), nativeFiles.count < 32 { nativeFiles.append(path) }
        }
        let directoryEnd = encryptedDirectoryEnd ?? reader.position
        if encryptedDirectoryEnd != nil, reader.position != reader.size { throw PackError.invalid("Encrypted directory contains unexpected trailing data.") }
        for (start, end) in ranges {
            guard start >= headerSize, end <= directoryStart || start >= directoryEnd else {
                throw PackError.invalid("PCK asset overlaps its header or directory.")
            }
        }
        guard hasProject else { throw PackError.invalid("No project settings found. This is a resource-only or incomplete pack.") }
        if encryptedScripts > 0 && ((major == 3 && decryptScript == nil) || (major == 4 && decryptBlock == nil) || ![3, 4].contains(major)) {
            throw PackError.encryptedScripts(major: major, count: encryptedScripts, example: encryptedExample)
        }
        var verifiedEncryptedFile = false
        func readAsset(_ asset: PackAsset, limit: UInt64, prefix: Int? = nil) throws -> Data {
            try file.seek(asset.offset)
            if asset.encrypted {
                guard let decrypt = decryptBlock else { throw PackError.encryptedPack(major: major) }
                let block = try file.encryptedBlock(magic: false, limit: limit, expectedSize: asset.size)
                let plain = try decrypt(block, false)
                guard UInt64(plain.count) == asset.size else { throw PackError.invalid("Invalid decrypted asset length: \(asset.path)") }
                verifiedEncryptedFile = true
                return prefix.map { Data(plain.prefix($0)) } ?? plain
            }
            guard prefix != nil || asset.size <= limit else { throw PackError.invalid("Asset exceeds inspection budget: \(asset.path)") }
            return try file.read(prefix.map { min($0, Int(asset.size)) } ?? Int(asset.size))
        }
        func validateVersion(_ bytes: Data, path: String, decrypted: Bool = false) throws -> UInt32 {
            guard bytes.count >= 8, bytes.prefix(4) == Data("GDSC".utf8) else { throw PackError.invalid("Invalid compiled script signature: \(path)") }
            let version = bytes[4..<8].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            if major == 4 && ![100, 101].contains(version) { throw PackError.invalid("\(path) uses unsupported compiled GDScript version \(version). This player reads formats 100 and 101. The pack has not been launched, to avoid an engine crash.") }
            if major == 3 && version > 13 {
                if decrypted { throw PackError.invalid("Decrypted script needs a newer Godot 3 bytecode reader.") }
                throw PackError.invalid("\(path) needs newer compiled scripts than Godot 3.6.3 can read. For APK assets, check the engine-family hint; Godot 4 scripts cannot run in Godot 3.")
            }
            return version
        }
        var versions = Set<UInt32>()
        for asset in encryptedEntries {
            guard asset.size >= 48, asset.size <= 16 * 1024 * 1024 else { throw PackError.invalid("Unsupported encrypted script size: \(asset.path)") }
            let bytes = try readAsset(asset, limit: 16 * 1024 * 1024)
            let plain = major == 3 ? try decryptScript!(bytes) : try decryptBlock!(bytes, true)
            guard plain.count >= 12 else { throw PackError.invalid("Invalid decrypted script: \(asset.path)") }
            versions.insert(try validateVersion(plain, path: asset.path, decrypted: true))
        }
        for asset in compiledScripts {
            guard asset.size >= 12 else { throw PackError.invalid("Truncated compiled script: \(asset.path)") }
            versions.insert(try validateVersion(readAsset(asset, limit: 16 * 1024 * 1024, prefix: 8), path: asset.path))
        }
        if let asset = binarySettings {
            guard asset.size >= 4 else { throw PackError.invalid("Truncated project.binary.") }
            guard try readAsset(asset, limit: 64 * 1024 * 1024, prefix: 4) == Data("ECFG".utf8) else { throw PackError.invalid("Invalid project.binary signature.") }
        }
        if flags & 1 == 0 && !encryptedFiles.isEmpty && !verifiedEncryptedFile {
            guard let sample = encryptedFiles.first(where: { $0.size <= 64 * 1024 * 1024 }) else { throw PackError.invalid("No encrypted asset fits the 64 MB key-validation budget. Import an unencrypted export.") }
            _ = try readAsset(sample, limit: 64 * 1024 * 1024)
        }
        // Directory-key validation completes before reporting a different
        // unsupported runtime, so recovery never confuses it with a bad key.
        if let example = dotnetExample {
            throw PackError.unsupportedRuntime("This game requires C#/.NET (\(example)). Its managed runtime is not included in this build of Hollow. Windows .NET DLLs cannot be launched by the bundled GDScript runtime.")
        }
        return PackInfo(format: format, major: major, minor: minor, patch: patch, fileCount: count, byteCount: packSize, nativeFiles: nativeFiles.isEmpty ? nil : nativeFiles, scriptVersions: versions.isEmpty ? nil : versions.sorted(), encryptedScriptCount: encryptedScripts == 0 ? nil : encryptedScripts, encryptedFileCount: encryptedFiles.isEmpty ? nil : encryptedFiles.count, encryptedDirectory: flags & 1 != 0)
    }
}

private struct PackAsset {
    let offset: UInt64
    let size: UInt64
    let path: String
    let encrypted: Bool
}

private final class PackReader {
    let handle: FileHandle?
    let buffer: Data?
    let size: UInt64
    var position: UInt64 = 0
    init(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        handle = file; buffer = nil
        size = try file.seekToEnd()
        try file.seek(toOffset: 0)
    }
    init(data: Data) { handle = nil; buffer = data; size = UInt64(data.count) }
    deinit { try? handle?.close() }
    func seek(_ offset: UInt64) throws {
        guard offset <= size else { throw PackError.invalid("PCK directory offset exceeds file size.") }
        try handle?.seek(toOffset: offset)
        position = offset
    }
    func read(_ count: Int) throws -> Data {
        guard UInt64(count) <= size - position else { throw PackError.invalid("Truncated PCK.") }
        let data: Data
        if let buffer = buffer { data = Data(buffer[Int(position)..<Int(position) + count]) }
        else { data = try handle?.read(upToCount: count) ?? Data() }
        guard data.count == count else { throw PackError.invalid("Truncated PCK.") }
        position += UInt64(count)
        return data
    }
    func u32() throws -> UInt32 { try read(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) } }
    func u64() throws -> UInt64 { try read(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) } }
    func encryptedBlock(magic: Bool, limit: UInt64, expectedSize: UInt64? = nil) throws -> Data {
        let header = try read(magic ? 44 : 40)
        let at = magic ? 20 : 16
        if magic && header.prefix(4) != Data("GDEC".utf8) { throw PackError.invalid("Invalid encrypted data signature.") }
        let length = header[at..<at + 8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        guard length <= limit, expectedSize == nil || expectedSize == length else { throw PackError.invalid("Encrypted data exceeds its inspection budget or declared asset size.") }
        return header + (try read(Int((length + 15) & ~UInt64(15))))
    }
}
