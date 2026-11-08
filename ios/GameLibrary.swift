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

    var controls: ControlProfile {
        var profile = controlProfile ?? .legacy(directions: directionKeys, extras: extraKeys)
        profile.constrain()
        return profile
    }
}

enum RuntimeSelection {
    static func problem(for game: Game) -> String? {
        if game.runtime == "godot3" || game.pack.major == 3 {
            return "Godot 3 is not bundled yet. This pack cannot run in the Godot 4 adapter."
        }
        guard game.pack.major == 4 else { return "Only Godot 4 projects can run in this build." }
        guard game.pack.minor <= 7 else { return "This pack needs a newer Godot runtime than 4.7.2." }
        if !(game.pack.nativeFiles ?? []).isEmpty, game.allowNativeFallback != true {
            return "This pack includes native components. Enable ‘Try without native extensions’ to attempt offline play. Features that depend on those components will not work."
        }
        return nil
    }
}

final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var error: String?
    @Published var importing = false
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

    private func persist(_ updated: [Game]) throws {
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

    func importPack(_ source: URL, replacing existing: Game? = nil) {
        guard !importing else { return }
        guard manifestUsable else { error = "The library manifest needs recovery before importing."; return }
        importing = true
        let staging = root.appendingPathComponent("import-\(UUID().uuidString).pck")
        DispatchQueue.global(qos: .userInitiated).async {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let result: Result<PackInfo, Error> = Result {
                guard source.isFileURL, source.pathExtension.lowercased() == "pck" else { throw PackError.invalid("Choose a standalone .pck file.") }
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                    do {
                        let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PackError.invalid("The selected item is not a regular file.") }
                        try self.files.copyItem(at: readable, to: staging)
                    } catch { copyError = error }
                }
                if let error = coordinationError { throw error }
                if let error = copyError { throw error }
                return try PCKInspector.inspect(staging)
            }
            DispatchQueue.main.async {
                defer { self.importing = false; try? self.files.removeItem(at: staging) }
                do {
                    let info = try result.get()
                    var game = existing ?? Game(id: UUID(), name: source.deletingPathExtension().lastPathComponent, pack: info)
                    game.pack = info
                    try self.files.createDirectory(at: self.directory(game.id), withIntermediateDirectories: true)
                    let destination = self.packURL(game)
                    let backup = self.directory(game.id).appendingPathComponent("previous.pck")
                    if existing != nil {
                        // Atomic replacement leaves the old pack intact on a failed copy.
                        if self.files.fileExists(atPath: backup.path) { try self.files.removeItem(at: backup) }
                        _ = try self.files.replaceItemAt(destination, withItemAt: staging, backupItemName: "previous.pck", options: .withoutDeletingBackupItem)
                    } else {
                        try self.files.moveItem(at: staging, to: destination)
                    }
                    do {
                        try self.persist(existing == nil ? self.games + [game] : self.games.map { $0.id == game.id ? game : $0 })
                    } catch {
                        if existing != nil, self.files.fileExists(atPath: backup.path) {
                            _ = try? self.files.replaceItemAt(destination, withItemAt: backup)
                        } else if existing == nil {
                            try? self.files.removeItem(at: self.directory(game.id))
                        }
                        throw error
                    }
                    try? self.files.removeItem(at: backup)
                } catch { self.error = "Import failed: \(error.localizedDescription)" }
            }
        }
    }

    func prepare(_ game: Game) throws {
        // Reinspect the private copy immediately before native initialization.
        let info = try PCKInspector.inspect(packURL(game))
        var checked = game
        checked.pack = info
        if let reason = RuntimeSelection.problem(for: checked) { throw PackError.invalid(reason) }
        try files.createDirectory(at: saveURL(game), withIntermediateDirectories: true)
    }
}
