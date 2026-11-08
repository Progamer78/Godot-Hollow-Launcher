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
    var version: String { "\(major).\(minor).\(patch)" }
}

enum PackError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

// Implements PackedSourcePCK::try_open_pack in the pinned official engine.
// Inspect only the header and directory; game assets are never extracted.
enum PCKInspector {
    static func inspect(_ url: URL) throws -> PackInfo {
        let reader = try PackReader(url)
        guard try reader.u32() == 0x43504447 else { throw PackError.invalid("Not a standalone Godot PCK (GDPC header missing).") }
        let format = try reader.u32()
        let major = try reader.u32(), minor = try reader.u32(), patch = try reader.u32()
        guard (1...4).contains(format) else { throw PackError.invalid("Unsupported pack format \(format).") }
        let headerSize: UInt64 = format == 1 ? 84 : (format == 2 ? 96 : 104)
        var flags: UInt32 = 0, base: UInt64 = 0
        if format >= 2 {
            flags = try reader.u32()
            guard flags & ~UInt32(7) == 0 else { throw PackError.invalid("Unknown PCK header flags.") }
            guard flags & 1 == 0 else { throw PackError.invalid("Encrypted pack directories require an unavailable export key.") }
            guard flags & 4 == 0 else { throw PackError.invalid("Sparse packs require external files; import a complete standalone pack.") }
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
        guard count > 0, count <= 1_000_000, UInt64(count) <= (reader.size - reader.position) / 36 else {
            throw PackError.invalid("Invalid or oversized PCK directory.")
        }
        var names = Set<String>(), hasProject = false
        var binarySettings: (UInt64, UInt64)?
        var ranges: [(UInt64, UInt64)] = []
        var nativeFiles: [String] = []
        var encryptedScripts = 0
        var encryptedExample = ""
        var compiledScripts: [(UInt64, UInt64, String)] = []
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
            guard fileFlags == 0 else { throw PackError.invalid("Encrypted, removal, delta, or unknown entries are unsupported; this may be a patch pack.") }
            guard base <= reader.size, offset <= reader.size - base, size <= reader.size - base - offset else {
                throw PackError.invalid("PCK asset lies outside the file: \(path)")
            }
            if size > 0 { ranges.append((base + offset, base + offset + size)) }
            hasProject = hasProject || path == "project.binary" || path == "project.godot"
            if path == "project.binary" { binarySettings = (base + offset, size) }
            if path == "project.godot", size == 0 { throw PackError.invalid("Empty project settings file.") }
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "gde" {
                encryptedScripts += 1
                if encryptedExample.isEmpty || encryptedExample.hasPrefix("addons/") { encryptedExample = path }
            }
            if ext == "cs" { throw PackError.invalid("\(path) requires a .NET runtime, which is not included in this player.") }
            if ext == "gdc" { compiledScripts.append((base + offset, size, path)) }
            if ["gdextension", "gdnlib", "dll", "so", "dylib"].contains(ext), nativeFiles.count < 32 { nativeFiles.append(path) }
        }
        let directoryEnd = reader.position
        for (start, end) in ranges {
            guard start >= headerSize, end <= directoryStart || start >= directoryEnd else {
                throw PackError.invalid("PCK asset overlaps its header or directory.")
            }
        }
        guard hasProject else { throw PackError.invalid("No project settings found. This is a resource-only or incomplete pack.") }
        if encryptedScripts > 0 {
            throw PackError.invalid("This Godot \(major) pack contains \(encryptedScripts) encrypted scripts (.gde), including \(encryptedExample). This player cannot decrypt them without the game's export encryption key. Use an unencrypted game export; changing the renderer or adding Godot 3 support cannot remove encryption.")
        }
        var versions = Set<UInt32>()
        for (offset, length, path) in compiledScripts {
            guard length >= 12 else { throw PackError.invalid("Truncated compiled script: \(path)") }
            try reader.seek(offset)
            guard try reader.read(4) == Data("GDSC".utf8) else { throw PackError.invalid("Invalid compiled script signature: \(path)") }
            let version = try reader.u32()
            versions.insert(version)
            if major == 4 && ![100, 101].contains(version) {
                throw PackError.invalid("\(path) uses unsupported compiled GDScript version \(version). This player reads formats 100 and 101. The pack has not been launched, to avoid an engine crash.")
            }
        }
        if let (offset, length) = binarySettings {
            guard length >= 4 else { throw PackError.invalid("Truncated project.binary.") }
            try reader.seek(offset)
            guard try reader.read(4) == Data("ECFG".utf8) else { throw PackError.invalid("Invalid project.binary signature.") }
        }
        return PackInfo(format: format, major: major, minor: minor, patch: patch, fileCount: count, byteCount: reader.size, nativeFiles: nativeFiles.isEmpty ? nil : nativeFiles, scriptVersions: versions.isEmpty ? nil : versions.sorted())
    }
}

private final class PackReader {
    let handle: FileHandle
    let size: UInt64
    var position: UInt64 = 0
    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
    }
    deinit { try? handle.close() }
    func seek(_ offset: UInt64) throws {
        guard offset <= size else { throw PackError.invalid("PCK directory offset exceeds file size.") }
        try handle.seek(toOffset: offset)
        position = offset
    }
    func read(_ count: Int) throws -> Data {
        guard UInt64(count) <= size - position else { throw PackError.invalid("Truncated PCK.") }
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw PackError.invalid("Truncated PCK.") }
        position += UInt64(count)
        return data
    }
    func u32() throws -> UInt32 { try read(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) } }
    func u64() throws -> UInt64 { try read(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) } }
}
