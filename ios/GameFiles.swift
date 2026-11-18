import Foundation

// Files kept beside a desktop game's executable, separate from user:// saves.
enum GameFiles {
    static func staging(for pack: URL) -> URL { pack.appendingPathExtension("files") }
    static func safe(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("\\") && !name.contains(":") && !name.contains("\0") &&
        !name.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
    static func installable(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !["exe", "dll", "so", "dylib", "a", "pdb", "tmp"].contains(ext) &&
            !name.split(separator: "/").contains("__MACOSX")
    }
    // Portable managed assemblies are handled by the interpreter, never dlopen.
    static func managed(_ name: String) -> Bool {
        let parts = name.split(separator: "/")
        return parts.count >= 2 && parts[0].hasPrefix("data_") && name.lowercased().hasSuffix(".dll")
    }
    static func externalAssembly(in root: URL?) -> Bool {
        guard let root = root, let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return false }
        return dirs.contains { dir in
            guard dir.lastPathComponent.hasPrefix("data_"), let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return false }
            return files.contains { $0.pathExtension.lowercased() == "dll" && !$0.lastPathComponent.lowercased().hasPrefix("system.") && !$0.lastPathComponent.lowercased().hasPrefix("microsoft.") && $0.lastPathComponent != "GodotSharp.dll" && $0.lastPathComponent != "mscorlib.dll" && $0.lastPathComponent != "netstandard.dll" && $0.lastPathComponent != "coreclr.dll" && $0.lastPathComponent != "hostfxr.dll" && $0.lastPathComponent != "hostpolicy.dll" && $0.lastPathComponent != "clrjit.dll" && $0.lastPathComponent != "mscordaccore.dll" && $0.lastPathComponent != "mscordbi.dll" }
        }
    }
    static func extract(_ archive: URL, entries: [ArchiveEntry], prefix: String, to root: URL, excluding: Set<String> = []) throws {
        let selected = entries.filter { !$0.directory && $0.name.hasPrefix(prefix) && !excluding.contains($0.name) }
            .map { ($0, String($0.name.dropFirst(prefix.count))) }
            .filter { installable($0.1) || managed($0.1) }
        guard selected.count <= 100000 else { throw PackError.invalid("Game Files contains too many entries.") }
        var total: UInt64 = 0
        for (entry, name) in selected {
            guard safe(name), entry.size <= 4 << 30, total <= (16 << 30) - entry.size else { throw PackError.invalid("Unsafe or oversized Game Files archive.") }
            total += entry.size
        }
        try PackageImport.checkSpace(root, bytes: total)
        for (entry, name) in selected {
            let destination = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PackageImport.extract(archive, entry: entry, destination: destination, limit: 4 << 30)
        }
    }
    static func copyCompanions(from source: URL, to destination: URL, excluding: Set<String>) throws {
        let files = try SafeFiles.children(source).filter { !excluding.contains($0.1) && (installable($0.1) || managed($0.1)) }
        try PackageImport.checkSpace(destination, bytes: files.reduce(UInt64(0)) { $0 + UInt64($1.2) })
        for (file, name, _) in files {
            let target = destination.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: target)
        }
    }
    // Move only incoming files. Retain unrelated existing assets without making
    // another copy of a multi-gigabyte library; roll back all replacements on error.
    static func merge(_ incoming: URL, into target: URL, commit: () throws -> Void = {}) throws {
        let fm = FileManager.default
        let files = try SafeFiles.children(incoming)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let backup = target.deletingLastPathComponent().appendingPathComponent("rollback-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: backup) }
        var moved: [(URL, URL?)] = []
        do {
            for (source, name, _) in files {
                guard safe(name) else { throw PackError.invalid("Unsafe Game Files path.") }
                let destination = target.appendingPathComponent(name)
                var parent = destination
                while parent.path != target.deletingLastPathComponent().path {
                    if fm.fileExists(atPath: parent.path), try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw PackError.invalid("Symbolic links are not allowed in Game Files.") }
                    if parent.path == target.path { break }; parent.deleteLastPathComponent()
                }
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                var old: URL?
                if fm.fileExists(atPath: destination.path) {
                    let saved = backup.appendingPathComponent(name)
                    try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: destination, to: saved); old = saved
                }
                moved.append((destination, old))
                try fm.moveItem(at: source, to: destination)
            }
            try commit()
        } catch {
            for (destination, old) in moved.reversed() {
                try? fm.removeItem(at: destination)
                if let old = old { try? fm.moveItem(at: old, to: destination) }
            }
            throw error
        }
    }
}

