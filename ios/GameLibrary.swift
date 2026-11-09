import Foundation
import Combine

struct Game: Codable, Identifiable {
    let id: UUID
    var name: String
    var pack: PackInfo
    var runtime = "automatic"
    var renderer = "project"
    var showControls = true
    var directionKeys = "arrows"
    var extraKeys = "Space,Shift"
    // Optional fields preserve manifests written by the first installed player.
    var controlProfile: ControlProfile?
    var allowNativeFallback: Bool?
    var orientation: String?
    var favorite: Bool?
    var collection: String?
    var notes: String?
    var lastPlayed: Date?
    var playedSeconds: Double?
    var importNote: String?
    var frameLimit: Int?
    var savedCheats: [SavedCheat]?
    var displayInset: Double?
    var displayOrientation: String {
        let value = orientation ?? "automatic"
        return ["portrait", "landscape"].contains(value) ? value : "automatic"
    }

    var controls: ControlProfile {
        var profile = controlProfile ?? .legacy(directions: directionKeys, extras: extraKeys)
        profile.constrain()
        return profile
    }
}

enum RuntimeSelection {
    static func unbundledNativeFiles(for game: Game) -> [String] {
        (game.pack.nativeFiles ?? []).filter { path in
            !(game.pack.major == 4 && path.lowercased().hasSuffix("/limboai.gdextension"))
        }
    }
    static func problem(for game: Game) -> String? {
        if (game.runtime == "godot3" && game.pack.major != 3) || (game.runtime == "godot4" && game.pack.major != 4) {
            return "The selected runtime must match the pack's Godot major version."
        }
        guard [3, 4].contains(game.pack.major) else { return "This player supports Godot 3 and 4 projects." }
        if game.pack.major == 4 && game.pack.minor > 7 { return "This pack needs a newer Godot runtime than 4.7.2." }
        if game.pack.major == 3 && game.pack.minor > 6 { return "This pack needs a newer Godot 3 runtime than 3.6.3." }
        let unbundled = unbundledNativeFiles(for: game)
        if !unbundled.isEmpty, game.allowNativeFallback != true {
            return "This pack includes native components. Enable ‘Try without native extensions’ to attempt offline play. Features that depend on those components will not work."
        }
        return nil
    }
}

final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var error: String?
    @Published var importing = false
    @Published private(set) var pendingImport: ImportCandidate?
    private var manifestUsable = true
    private let files = FileManager.default
    let root: URL
    let saves: URL
    private var manifest: URL { root.appendingPathComponent("library.json") }

    init(storageRoot: URL? = nil, savesRoot: URL? = nil) {
        root = storageRoot ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GodotPlayer")
        saves = savesRoot ?? files.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("GodotPlayerSaves")
        do {
            try files.createDirectory(at: root.appendingPathComponent("Games"), withIntermediateDirectories: true)
            try files.createDirectory(at: saves, withIntermediateDirectories: true)
            if files.fileExists(atPath: manifest.path) {
                games = try JSONDecoder().decode([Game].self, from: Data(contentsOf: manifest))
                guard Set(games.map(\.id)).count == games.count else { throw PackError.invalid("Duplicate IDs in library manifest.") }
            }
        } catch {
            manifestUsable = false
            self.error = "Cannot load game library: \(error.localizedDescription). Library changes are disabled to preserve existing files."
        }
    }

    func directory(_ id: UUID) -> URL { root.appendingPathComponent("Games/\(id.uuidString)") }
    func packURL(_ game: Game) -> URL { directory(game.id).appendingPathComponent("game.pck") }
    func saveURL(_ game: Game) -> URL { saves.appendingPathComponent(game.id.uuidString) }

    func persist(_ updated: [Game]) throws {
        guard manifestUsable else { throw PackError.invalid("The library manifest needs recovery before changes can be saved.") }
        try JSONEncoder().encode(updated).write(to: manifest, options: .atomic)
        games = updated
    }

    func update(_ game: Game) {
        do { try persist(games.map { $0.id == game.id ? game : $0 }) }
        catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func saveControls(_ profile: ControlProfile, visible: Bool, for id: UUID) -> Bool {
        guard var game = games.first(where: { $0.id == id }) else { error = "Game no longer exists in the library."; return false }
        var checked = profile
        checked.constrain()
        game.controlProfile = checked
        game.showControls = visible
        do { try persist(games.map { $0.id == id ? game : $0 }); return true }
        catch { self.error = "Could not save controls: \(error.localizedDescription)"; return false }
    }

    func delete(_ game: Game) {
        do {
            // Remove the manifest entry before deleting files. UUIDs, never PCK
            // paths or user names, select directories for filesystem mutations.
            try persist(games.filter { $0.id != game.id })
            try files.removeItem(at: directory(game.id))
            if files.fileExists(atPath: saveURL(game).path) { try files.removeItem(at: saveURL(game)) }
        } catch { self.error = error.localizedDescription }
    }

    func importPack(_ source: URL, companion: URL? = nil, replacing existing: Game? = nil, engineHint: UInt32? = nil) {
        guard !importing, pendingImport == nil else { return }
        guard manifestUsable else { error = "The library manifest needs recovery before importing."; return }
        importing = true
        let staging = root.appendingPathComponent("import-\(UUID().uuidString).pck")
        DispatchQueue.global(qos: .userInitiated).async {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let companionAccess = companion?.startAccessingSecurityScopedResource() ?? false
            defer { if companionAccess { companion?.stopAccessingSecurityScopedResource() } }
            let result: Result<(PackInfo, String?, Data?), Error> = Result {
                if let companion = companion, !companion.isFileURL || companion.pathExtension.lowercased() != "exe" { throw PackError.invalid("The companion must be the original EXE file.") }
                guard source.isFileURL, PackageImport.extensions.contains(source.pathExtension.lowercased()) else { throw PackError.invalid("Choose a PCK, ZIP, APK, or embedded-PCK EXE.") }
                var coordinationError: NSError?
                var copyError: Error?
                var note: String?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                    do {
                        let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PackError.invalid("The selected item is not a regular file.") }
                        note = try PackageImport.prepare(readable, destination: staging, engineHint: engineHint)
                    } catch { copyError = error }
                }
                if let error = coordinationError { throw error }
                if let error = copyError { throw error }
                let original = companion ?? (source.pathExtension.lowercased() == "exe" ? source : nil)
                if let original = original {
                    var recovered: (PackInfo, Data?)?
                    var recoveryError: Error?
                    var recoveryCoordination: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: original, options: [], error: &recoveryCoordination) { readable in
                        do {
                            let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PackError.invalid("Choose a regular original EXE.") }
                            recovered = try ExecutableImport.recover(executable: readable, pack: staging)
                        } catch { recoveryError = error }
                    }
                    if let error = recoveryCoordination { throw error }
                    if let error = recoveryError { throw error }
                    guard let recovered = recovered else { throw PackError.invalid("Original executable could not be inspected.") }
                    if recovered.1 != nil { note = (note.map { $0 + " " } ?? "") + "Original runtime script key recovered and all encrypted scripts validated. Game files are unchanged." }
                    return (recovered.0, note, recovered.1)
                }
                let key = try existing.flatMap { try self.scriptKey($0) }
                let info = try ExecutableImport.inspect(staging, key: key)
                return (info, note, (info.encryptedScriptCount ?? 0) > 0 ? key : nil)
            }
            DispatchQueue.main.async {
                defer { self.importing = false }
                do {
                    let (info, note, key) = try result.get()
                    if let game = existing {
                        self.pendingImport = ImportCandidate(game: game, pack: info, note: note, staging: staging, key: key)
                        return
                    }
                    defer { try? self.files.removeItem(at: staging) }
                    try self.install(staging: staging, info: info, note: note, name: source.deletingPathExtension().lastPathComponent, existing: nil, key: key)
                } catch { try? self.files.removeItem(at: staging); self.error = "Import failed: \(error.localizedDescription)" }
            }
        }
    }

    private func install(staging: URL, info: PackInfo, note: String?, name: String, existing: Game?, key: Data?) throws {
        var game: Game
        if let existing = existing {
            guard let current = games.first(where: { $0.id == existing.id }) else { throw PackError.invalid("The game was removed while importing.") }
            game = current
            if current.pack.major != info.major { game.runtime = "automatic"; game.renderer = "project" }
        } else { game = Game(id: UUID(), name: name, pack: info) }
        game.pack = info
        game.importNote = note
        try self.files.createDirectory(at: self.directory(game.id), withIntermediateDirectories: true)
        let destination = self.packURL(game)
        let backup = self.directory(game.id).appendingPathComponent("previous.pck")
        let previousKey = try existing.flatMap { try scriptKey($0) }
        if existing != nil {
            // Atomic replacement leaves the old pack intact on a failed copy.
            if self.files.fileExists(atPath: backup.path) { try self.files.removeItem(at: backup) }
            _ = try self.files.replaceItemAt(destination, withItemAt: staging, backupItemName: "previous.pck", options: .withoutDeletingBackupItem)
        } else {
            try self.files.moveItem(at: staging, to: destination)
        }
        do {
            try storeKey(key, game: game)
            try self.persist(existing == nil ? self.games + [game] : self.games.map { $0.id == game.id ? game : $0 })
        } catch {
            try? storeKey(previousKey, game: game)
            if existing != nil, self.files.fileExists(atPath: backup.path) {
                _ = try? self.files.replaceItemAt(destination, withItemAt: backup)
            } else if existing == nil {
                try? self.files.removeItem(at: self.directory(game.id))
            }
            throw error
        }
        try? self.files.removeItem(at: backup)
    }


    func cancelImport() {
        guard !importing else { return }
        if let pending = pendingImport { try? files.removeItem(at: pending.staging) }
        pendingImport = nil
    }
    func confirmImport() {
        guard !importing, let pending = pendingImport else { return }
        importing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.vault.backup(pending.game.id, label: "Automatic: before game replacement") }
            DispatchQueue.main.async {
                defer { self.importing = false; self.pendingImport = nil; try? self.files.removeItem(at: pending.staging) }
                do {
                    _ = try result.get()
                    try self.install(staging: pending.staging, info: pending.pack, note: pending.note, name: pending.game.name, existing: pending.game, key: pending.key)
                } catch { self.error = "Replacement failed: \(error.localizedDescription)" }
            }
        }
    }

    func prepare(_ game: Game) throws {
        // Reinspect the private copy immediately before native initialization.
        let info = try ExecutableImport.inspect(packURL(game), key: scriptKey(game))
        var checked = game
        checked.pack = info
        if let reason = RuntimeSelection.problem(for: checked) { throw PackError.invalid(reason) }
        try files.createDirectory(at: saveURL(game), withIntermediateDirectories: true)
        _ = try vault.backup(game.id, label: "Automatic: before launch")
    }

    var vault: SaveVault { SaveVault(root: root.appendingPathComponent("Backups"), saves: saves) }
    func scriptKey(_ game: Game) throws -> Data? {
        let url = directory(game.id).appendingPathComponent("script-key.bin")
        guard files.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == 32 else { throw PackError.invalid("The private script key needs reimporting from the original EXE.") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 33) ?? Data()
        guard data.count == 32 else { throw PackError.invalid("Invalid private script key length.") }
        return data
    }
    private func storeKey(_ key: Data?, game: Game) throws {
        let url = directory(game.id).appendingPathComponent("script-key.bin")
        if let key = key {
            guard key.count == 32 else { throw PackError.invalid("Invalid private script key length.") }
            #if os(iOS)
            try key.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try key.write(to: url, options: .atomic)
            #endif
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }
    func journal(_ game: Game, status: String) {
        do {
            try JSONEncoder().encode(LaunchJournal(status: status, date: Date())).write(to: directory(game.id).appendingPathComponent("launch.json"), options: .atomic)
        } catch { self.error = "Could not record launch status: \(error.localizedDescription)" }
    }
    func previousLaunch(_ game: Game) -> LaunchJournal? {
        guard let data = try? Data(contentsOf: directory(game.id).appendingPathComponent("launch.json")) else { return nil }
        return try? JSONDecoder().decode(LaunchJournal.self, from: data)
    }
    func markPlayed(_ id: UUID, seconds: Double = 0) {
        guard var game = games.first(where: { $0.id == id }) else { return }
        game.lastPlayed = Date(); game.playedSeconds = (game.playedSeconds ?? 0) + max(0, seconds)
        update(game)
    }
}

struct LaunchJournal: Codable { let status: String; let date: Date }
struct ImportCandidate: Identifiable {
    let id = UUID()
    let game: Game
    let pack: PackInfo
    let note: String?
    let staging: URL
    let key: Data?
}
