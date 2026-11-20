import Foundation

enum SaveTextFormat {
    static func json(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}

struct SaveSnapshot: Codable, Identifiable {
    let id: UUID
    let created: Date
    let label: String
    let bytes: Int64
}

struct BackupPolicy: Codable {
    var beforeLaunch = true
    var beforeTools = true
    var beforeReplacement = true
    var count = 5
    var budgetMB = 1024
    mutating func constrain() { count = min(20, max(1, count)); budgetMB = min(8192, max(64, budgetMB)) }
}

enum SafeFiles {
    static func children(_ root: URL, excluding: Set<String> = [], directory: ((String) throws -> Void)? = nil) throws -> [(URL, String, Int64)] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PackError.invalid("Symbolic links are not allowed in save folders.") }
        var result: [(URL, String, Int64)] = []; var total: Int64 = 0; var enumerationError: Error?
        var visited = 0
        // Foundation may expand an ancestor alias such as /var -> /private/var
        // in enumerated URLs. Use the same canonical root for enumeration,
        // containment and relative names so exclusions and restored paths agree.
        guard let iterator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw PackError.invalid("Cannot read the save folder; no backup was created.") }
        for case let url as URL in iterator {
            visited += 1
            guard visited <= 100000 else { throw PackError.invalid("Save folder has too many files or directories to back up.") }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard values.isSymbolicLink != true, canonicalPath.hasPrefix(base.path + "/") else { throw PackError.invalid("Unsafe save file or symbolic link.") }
            let relative = String(canonicalPath.dropFirst(base.path.count + 1))
            if let first = relative.split(separator: "/").first, excluding.contains(String(first)) { if values.isDirectory == true { iterator.skipDescendants() }; continue }
            if values.isDirectory == true { try directory?(relative) }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard result.count < 100000, size <= 4 << 30, total <= (8 << 30) - size else { throw PackError.invalid("Save folder exceeds the 8 GB backup limit.") }
                total += size; result.append((url, relative, size))
            }
        }
        if let error = enumerationError { throw error }
        return result
    }
    static func copyTree(_ source: URL, to destination: URL, excluding: Set<String> = []) throws -> Int64 {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var size: Int64 = 0
        for (file, name, bytes) in try children(source, excluding: excluding, directory: { name in try FileManager.default.createDirectory(at: destination.appendingPathComponent(name), withIntermediateDirectories: true) }) {
            let target = destination.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: target); size += bytes
        }
        return size
    }
}

final class SaveVault {
    let root: URL
    let saves: URL
    init(root: URL, saves: URL) { self.root = root; self.saves = saves }
    private func gameRoot(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
    private func saveRoot(_ id: UUID) -> URL { saves.appendingPathComponent(id.uuidString) }
    static let excluded: Set<String> = ["player.log", "startup.log", "startup.previous.log", "logs", "shader_cache"]
    func policy(_ id: UUID) -> BackupPolicy {
        guard let data = UserDefaults.standard.data(forKey: "hollowBackupPolicy.\(id.uuidString)"),
              var result = try? JSONDecoder().decode(BackupPolicy.self, from: data) else { return BackupPolicy() }
        result.constrain(); return result
    }
    func setPolicy(_ id: UUID, _ policy: BackupPolicy) {
        var value = policy; value.constrain()
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "hollowBackupPolicy.\(id.uuidString)")
    }
    @discardableResult
    func automaticBackup(_ id: UUID, event: String) throws -> SaveSnapshot? {
        let settings = policy(id)
        if (event == "launch" && !settings.beforeLaunch) || (event == "tools" && !settings.beforeTools) || (event == "replacement" && !settings.beforeReplacement) { return nil }
        if try SafeFiles.children(saveRoot(id), excluding: Self.excluded).isEmpty { return nil }
        return try backup(id, label: "Automatic: before \(event)")
    }
    func pruneAutomatic(_ id: UUID) throws {
        let settings = policy(id)
        var total: Int64 = 0
        for (index, snapshot) in try snapshots(id).filter({ $0.label.hasPrefix("Automatic:") }).enumerated() {
            total += snapshot.bytes
            if index >= settings.count || total > Int64(settings.budgetMB) * 1024 * 1024 { try remove(id, snapshot: snapshot) }
        }
    }
    func snapshots(_ id: UUID) throws -> [SaveSnapshot] {
        guard FileManager.default.fileExists(atPath: gameRoot(id).path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: gameRoot(id), includingPropertiesForKeys: nil).compactMap { folder -> SaveSnapshot? in
            guard UUID(uuidString: folder.lastPathComponent) != nil else { return nil }
            return try JSONDecoder().decode(SaveSnapshot.self, from: Data(contentsOf: folder.appendingPathComponent("snapshot.json")))
        }.sorted { $0.created > $1.created }
    }
    @discardableResult
    func backup(_ id: UUID, label: String) throws -> SaveSnapshot {
        let sourceBytes = try SafeFiles.children(saveRoot(id), excluding: Self.excluded).reduce(Int64(0)) { $0 + $1.2 }
        if label.hasPrefix("Automatic:"), sourceBytes > Int64(policy(id).budgetMB) * 1024 * 1024 {
            throw PackError.invalid("These saves exceed this game's automatic-backup budget. Increase it in Saves & Backups or turn off the optional backup for this action. No existing saves or backups were deleted.")
        }
        if let free = try? root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < sourceBytes + 32 * 1024 * 1024 {
            throw PackError.invalid("Not enough free space to back up these saves safely. Free space or change this game's backup settings before trying again.")
        }
        let identity = UUID(); let folder = gameRoot(id).appendingPathComponent(identity.uuidString)
        let staging = gameRoot(id).appendingPathComponent("staging-\(identity.uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let bytes = try SafeFiles.copyTree(saveRoot(id), to: staging.appendingPathComponent("files"), excluding: Self.excluded)
        let snapshot = SaveSnapshot(id: identity, created: Date(), label: String(label.prefix(100)), bytes: bytes)
        try JSONEncoder().encode(snapshot).write(to: staging.appendingPathComponent("snapshot.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: folder)
        if label.hasPrefix("Automatic:") {
            try pruneAutomatic(id)
        }
        return snapshot
    }
    func restore(_ id: UUID, snapshot: SaveSnapshot) throws {
        let source = gameRoot(id).appendingPathComponent(snapshot.id.uuidString).appendingPathComponent("files")
        guard FileManager.default.fileExists(atPath: source.path) else { throw PackError.invalid("Backup files are missing.") }
        try replace(id, from: source, backupLabel: "Automatic: before restore")
    }
    private func replace(_ id: UUID, from source: URL, backupLabel: String) throws {
        let target = saveRoot(id)
        let staging = saves.appendingPathComponent("restore-\(UUID().uuidString)")
        let rollback = saves.appendingPathComponent("rollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        _ = try SafeFiles.copyTree(source, to: staging)
        // Stage the chosen snapshot before creating/pruning automatic backups;
        // the selected snapshot itself may be the oldest retained backup.
        _ = try backup(id, label: backupLabel)
        let existed = FileManager.default.fileExists(atPath: target.path)
        if existed { try FileManager.default.moveItem(at: target, to: rollback) }
        do { try FileManager.default.moveItem(at: staging, to: target) }
        catch {
            if existed { try? FileManager.default.moveItem(at: rollback, to: target) }
            throw error
        }
        if existed { try? FileManager.default.removeItem(at: rollback) }
    }
    func remove(_ id: UUID, snapshot: SaveSnapshot) throws {
        try FileManager.default.removeItem(at: gameRoot(id).appendingPathComponent(snapshot.id.uuidString))
    }
    func export(_ id: UUID, to url: URL) throws {
        var paths: [String] = [], names: [String] = []
        let files = try SafeFiles.children(saveRoot(id), excluding: Self.excluded, directory: { name in paths.append(self.saveRoot(id).appendingPathComponent(name).path); names.append(name + "/") })
        guard !files.isEmpty else { throw PackError.invalid("No save files to export yet. Save in the game first.") }
        try GPArchive.create(url.path, files: paths + files.map { $0.0.path }, names: names + files.map { $0.1 })
    }
    func importArchive(_ id: UUID, source: URL) throws {
        let staging = saves.appendingPathComponent("import-saves-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let all = try PackageImport.entries(source)
        guard all.count <= 100000 else { throw PackError.invalid("Save ZIP has too many entries.") }
        let entries = all.filter { !$0.directory }
        guard !entries.isEmpty, entries.count <= 100000, entries.reduce(UInt64(0), { $0 + $1.size }) <= 8 << 30 else { throw PackError.invalid("Save ZIP is empty or exceeds the 8 GB limit.") }
        guard Set(entries.map { $0.name.precomposedStringWithCanonicalMapping.lowercased() }).count == entries.count else { throw PackError.invalid("Save ZIP contains colliding filenames on this device.") }
        for entry in all where entry.directory { try FileManager.default.createDirectory(at: staging.appendingPathComponent(entry.name), withIntermediateDirectories: true) }
        for entry in entries {
            let target = staging.appendingPathComponent(entry.name)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw PackError.invalid("Save ZIP contains colliding file or directory names.") }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PackageImport.extract(source, entry: entry, destination: target, limit: 4 << 30)
        }
        try replace(id, from: staging, backupLabel: "Automatic: before save import")
    }
    func preview(_ id: UUID, name: String) throws -> String {
        guard let file = try SafeFiles.children(saveRoot(id)).first(where: { $0.1 == name }), file.2 <= 256 * 1024,
              ["json", "cfg", "ini", "txt", "csv"].contains(file.0.pathExtension.lowercased()) else { throw PackError.invalid("Preview supports UTF-8 text saves up to 256 KB.") }
        let input = try FileHandle(forReadingFrom: file.0); defer { try? input.close() }
        let bytes = try input.read(upToCount: 256 * 1024 + 1) ?? Data()
        guard bytes.count <= 256 * 1024, let text = String(data: bytes, encoding: .utf8) else { throw PackError.invalid("This save is too large or is not UTF-8 text.") }
        return text
    }
    func edit(_ id: UUID, name: String, original: String, text: String) throws {
        let data = Data(text.utf8)
        guard data.count <= 256 * 1024 else { throw PackError.invalid("Save editing supports text files up to 256 KB.") }
        guard try preview(id, name: name) == original else { throw PackError.invalid("This save changed after you opened it. Reopen the file before editing so newer progress is not overwritten.") }
        if (name as NSString).pathExtension.lowercased() == "json" {
            do { _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) }
            catch { throw PackError.invalid("This is not valid JSON. Check quotes, commas and brackets before saving. The original file is unchanged.") }
        }
        _ = try backup(id, label: "Automatic: before save edit")
        guard try preview(id, name: name) == original,
              let file = try SafeFiles.children(saveRoot(id)).first(where: { $0.1 == name }) else {
            throw PackError.invalid("This save changed while it was being backed up. Reopen it before editing.")
        }
        try data.write(to: file.0, options: .atomic)
    }
}
