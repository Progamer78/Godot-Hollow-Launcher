import SwiftUI
import UniformTypeIdentifiers

@main
struct GodotPlayerApp: App {
    @UIApplicationDelegateAdaptor(GDTApplicationDelegate.self) var appDelegate
    @StateObject private var library = GameLibrary()
    var body: some Scene {
        WindowGroup { PlayerRoot().environmentObject(library) }
    }
}

struct GameSession: Identifiable {
    let id: UUID
    let controller: UIViewController
    let game: Game
    let aspectRatio: Double
}

struct PlayerRoot: View {
    @EnvironmentObject var library: GameLibrary
    @State private var session: GameSession?
    @State private var picker = false
    @State private var replacement: Game?
    @State private var starting = false
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var importEngine = "automatic"
    @State private var sharedReport: URL?
    @State private var sharingReport = false
    @State private var layoutTarget: UUID?
    @State private var controllerTarget: Game?

    private var visibleGames: [Game] {
        library.games.filter { game in
            (!favoritesOnly || game.favorite == true) && (search.isEmpty || (game.name + " " + (game.collection ?? "")).localizedCaseInsensitiveContains(search))
        }.sorted {
            if ($0.favorite == true) != ($1.favorite == true) { return $0.favorite == true }
            return ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
        }
    }

    var body: some View {
        Group {
            if let session = session {
                GameScreen(session: session)
            } else {
                NavigationView {
                    List {
                        Section {
                            TextField("Search games or collections", text: $search)
                            Toggle("Favorites only", isOn: $favoritesOnly)
                            Picker("APK engine hint", selection: $importEngine) {
                                Text("Detect automatically").tag("automatic")
                                Text("Godot 3 assets").tag("3")
                                Text("Godot 4 assets").tag("4")
                            }
                            Text("Encrypted Godot 3 game? Select its original EXE and PCK together in Import Game.").font(.caption)
                        }
                        if library.games.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundColor(.blue)
                                Text("Your games, offline").font(.headline)
                                Text("Import a complete Godot 3 or 4 PCK to get started.").foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(visibleGames) { game in
                            NavigationLink(destination: details(game)) {
                                HStack(spacing: 14) {
                                    Image(systemName: "gamecontroller.fill").font(.title2)
                                        .foregroundColor(game.pack.major == 3 ? .orange : .blue)
                                        .frame(width: 44, height: 44)
                                        .background(Color.secondary.opacity(0.08)).cornerRadius(12)
                                    VStack(alignment: .leading, spacing: 4) {
                                    Text(game.name)
                                    if game.favorite == true { Image(systemName: "star.fill").font(.caption).foregroundColor(.yellow) }
                                    if let collection = game.collection, !collection.isEmpty { Text(collection).font(.caption).foregroundColor(.secondary) }
                                    Text("Godot \(game.pack.version) · \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
                                        .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }.onDelete { offsets in
                            let selected = offsets.map { visibleGames[$0] }
                            for game in selected { library.delete(game) }
                        }
                        Section(footer: Text("One game per app process. To return to the library, close the app from the app switcher and reopen it. Only import games you trust; scripts share the app's iOS sandbox.")) {
                            Label("Godot 3.6.3 + 4.7.2 · ARM64", systemImage: "cpu")
                        }
                    }
                    .navigationTitle("Godot Player")
                    .toolbar {
                        Button(library.importing ? "Importing…" : "Import Game") {
                            replacement = nil
                            layoutTarget = nil
                            picker = true
                        }.disabled(library.importing || starting)
                    }
                }.navigationViewStyle(StackNavigationViewStyle()).accentColor(.blue)
            }
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.data, .zip], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let id = layoutTarget {
                    guard urls.count == 1 else { library.error = "Choose one layout JSON."; return }
                    defer { layoutTarget = nil }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 256 * 1024 else { throw PackError.invalid("Choose a regular layout JSON file up to 256 KB.") }
                        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
                        let data = try input.read(upToCount: 256 * 1024 + 1) ?? Data()
                        guard data.count <= 256 * 1024 else { throw PackError.invalid("Layout JSON exceeds 256 KB.") }
                        var profile = try JSONDecoder().decode(ControlProfile.self, from: data); profile.constrain()
                        _ = library.saveControls(profile, visible: true, for: id)
                    } catch { library.error = error.localizedDescription }
                } else if urls.count == 1 { library.importPack(url, replacing: replacement, engineHint: UInt32(importEngine)) }
                else if urls.count == 2, let pack = urls.first(where: { $0.pathExtension.lowercased() == "pck" }), let exe = urls.first(where: { $0.pathExtension.lowercased() == "exe" }) {
                    library.importPack(pack, companion: exe, replacing: replacement, engineHint: UInt32(importEngine))
                } else { library.error = "Choose one game archive, or select its original EXE and PCK together for encrypted Godot 3 games." }
            case .failure(let error): layoutTarget = nil; library.error = error.localizedDescription
            }
        }
        .sheet(item:$controllerTarget) { game in
            ControllerEditor(profile:game.controls.controller ?? ControllerProfile(),onSave:{ controller in
                var profile=(library.games.first { $0.id == game.id } ?? game).controls
                profile.controller=controller
                _ = library.saveControls(profile,visible:game.showControls,for:game.id)
            })
        }
        .onOpenURL { url in
            if session == nil { library.importPack(url) }
            else { library.error = "Close the app from the app switcher and reopen it before importing another game." }
        }
        .sheet(isPresented: $sharingReport, onDismiss: { if let file = sharedReport { try? FileManager.default.removeItem(at: file) }; sharedReport = nil }) { if let file = sharedReport { ShareFiles(items: [file]) } }
        .sheet(item: Binding(get: { library.pendingImport }, set: { _ in library.cancelImport() })) { candidate in
            NavigationView {
                Form {
                    Text("Replace \(candidate.game.name)?").font(.headline)
                    Text("Engine metadata: \(candidate.game.pack.version) -> \(candidate.pack.version)")
                    Text("Files: \(candidate.game.pack.fileCount) -> \(candidate.pack.fileCount)")
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(candidate.game.pack.byteCount), countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: Int64(candidate.pack.byteCount), countStyle: .file))")
                    Text("Native descriptors: \((candidate.pack.nativeFiles ?? []).joined(separator: ", "))").font(.caption)
                    if let note = candidate.note { Text(note).font(.caption) }
                    Text("Saves and control layouts keep their identity. A save backup is created first, but the new game version may use an incompatible save format.")
                    if candidate.game.pack.major != candidate.pack.major { Text("The engine family changed. Runtime and renderer overrides will reset to automatic/project defaults.").foregroundColor(.orange) }
                    Button(library.importing ? "Backing up and replacing..." : "Back Up & Replace") { library.confirmImport() }.disabled(library.importing)
                    Button("Cancel") { library.cancelImport() }.disabled(library.importing)
                }.navigationTitle("Review Game Update")
            }.navigationViewStyle(StackNavigationViewStyle())
        }
        .alert(isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Alert(title: Text("Godot Player"), message: Text(library.error ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private func details(_ original: Game) -> some View {
        let game = library.games.first { $0.id == original.id } ?? original
        return Form {
            Section(header: Text("Game")) {
                TextField("Name", text: field(game, \.name))
                Toggle("Favorite", isOn: Binding(get: { game.favorite == true }, set: { value in var copy = game; copy.favorite = value; library.update(copy) }))
                TextField("Collection", text: Binding(get: { game.collection ?? "" }, set: { value in var copy = game; copy.collection = String(value.prefix(60)); library.update(copy) }))
                TextField("Your notes", text: Binding(get: { game.notes ?? "" }, set: { value in var copy = game; copy.notes = String(value.prefix(2000)); library.update(copy) }))
                Text("Detected engine: \(game.pack.version)")
                Text("Pack format: \(game.pack.format) · \(game.pack.fileCount) files")
                if let versions = game.pack.scriptVersions {
                    Text("Compiled scripts: \(versions.map { String($0) }.joined(separator: ", "))").font(.caption)
                }
                Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
                if let note = game.importNote { Text(note).font(.caption).foregroundColor(.secondary) }
                if let played = game.lastPlayed { Text("Last played: \(DateFormatter.localizedString(from: played, dateStyle: .medium, timeStyle: .short))").font(.caption) }
            }
            Section(header: Text("Launch & Compatibility")) {
                if let journal = library.previousLaunch(game), ["starting", "running", "failed"].contains(journal.status) {
                    Text(journal.status == "starting" || journal.status == "failed" ? "The previous launch did not finish. Try Safe Launch and export a support report." : "The previous session ended without a recorded background transition. It may have been closed or interrupted.").font(.caption).foregroundColor(.orange)
                }
                Text(RuntimeSelection.problem(for: game) ?? "Candidate for Godot \(game.pack.major == 3 ? "3.6.3" : "4.7.2"). Execution compatibility is checked by the engine.")
                if let nativeFiles = game.pack.nativeFiles, !nativeFiles.isEmpty {
                    Text("Native descriptors in this pack: \(nativeFiles.joined(separator: ", "))").font(.caption)
                    if game.pack.major == 4 && nativeFiles.contains(where: { $0.lowercased().hasSuffix("/limboai.gdextension") }) {
                        Text("LimboAI is built into this player. The pack's external library is not loaded.").font(.caption).foregroundColor(.secondary)
                    }
                    if !RuntimeSelection.unbundledNativeFiles(for: game).isEmpty {
                    Toggle("Try without native extensions", isOn: Binding(get: {
                        (library.games.first { $0.id == game.id } ?? game).allowNativeFallback == true
                    }, set: { value in
                        var updated = library.games.first { $0.id == game.id } ?? game
                        updated.allowNativeFallback = value
                        library.update(updated)
                    }))
                    Text("The original pack stays unchanged. Optional features such as WebRTC multiplayer may be unavailable; required native classes can prevent launch.").font(.caption)
                    }
                }
                Button(starting ? "Starting…" : "Play") { play(game) }
                    .disabled(starting || library.importing || RuntimeSelection.problem(for: game) != nil)
                Button("Replace PCK (keep saves)") { layoutTarget = nil; replacement = game; picker = true }.disabled(library.importing)
                Button("Safe Launch") {
                    var safe = game; safe.renderer = game.pack.major == 3 ? "gles2" : "gl_compatibility"; safe.showControls = false; safe.frameLimit = 30
                    play(safe)
                }.disabled(starting || library.importing || RuntimeSelection.problem(for: game) != nil)
                Text("Safe Launch uses OpenGL, a 30 FPS cap and hidden controls for this session. It cannot supply missing classes or decrypt scripts.").font(.caption)
            }
            Section(header: Text("Saves & support")) {
                NavigationLink("Saves, Backups & Transfers", destination: SaveManager(game: game))
                NavigationLink("Storage & Shader Cache", destination: StorageManager(game: game))
                Button("Export Support Report") {
                    do { sharedReport = try SupportReport.export(game: game, library: library); sharingReport = true }
                    catch { library.error = error.localizedDescription }
                }
                Text("Play time: \(Int((game.playedSeconds ?? 0) / 60)) minutes").font(.caption)
            }
            Section(header: Text("Control layouts")) {
                Button("Controller Bindings & Stick Mouse") { controllerTarget=game }
                Menu("Apply a Preset") {
                    ForEach(ControlProfile.presetNames, id: \.self) { name in
                        Button(name) { _ = library.saveControls(.preset(name), visible: true, for: game.id) }
                    }
                }
                Button("Import Layout JSON") { layoutTarget = game.id; picker = true }
                Button("Share Layout JSON") {
                    do {
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("GodotPlayer-layout-\(UUID().uuidString).json")
                        try JSONEncoder().encode(game.controls).write(to: file, options: .atomic)
                        sharedReport = file; sharingReport = true
                    } catch { library.error = error.localizedDescription }
                }
                Slider(value: profileField(game, \.opacity, fallback: 0.85), in: 0.2...1)
                Text("Control opacity: \(Int((game.controls.opacity ?? 0.85) * 100))%").font(.caption)
                Toggle("High contrast borders", isOn: profileField(game, \.highContrast, fallback: false))
                Toggle("Button haptics", isOn: profileField(game, \.haptics, fallback: false))
            }
            Section(header: Text("Launch settings")) {
                Picker("Runtime override", selection: field(game, \.runtime)) {
                    Text("Automatic").tag("automatic")
                    Text("Godot 4.7.2").tag("godot4")
                    Text("Godot 3.6.3").tag("godot3")
                }
                Picker("Renderer", selection: field(game, \.renderer)) {
                    Text("Project default").tag("project")
                    if game.pack.major == 3 {
                        Text("OpenGL ES 2").tag("gles2")
                        Text("OpenGL ES 3").tag("gles3")
                    } else {
                        Text("Mobile / Metal").tag("mobile")
                        Text("Compatibility / OpenGL").tag("gl_compatibility")
                    }
                }
                Picker("Frame cap", selection: Binding(get: { game.frameLimit ?? 0 }, set: { value in var copy = game; copy.frameLimit = value; library.update(copy) })) {
                    Text("Game default").tag(0); Text("Battery - 30 FPS").tag(30); Text("Balanced - 60 FPS").tag(60); Text("120 FPS").tag(120)
                }
                Slider(value: Binding(get: { game.displayInset ?? 0 }, set: { value in var copy = game; copy.displayInset = value; library.update(copy) }), in: 0...48, step: 2)
                Text("Game margin: \(Int(game.displayInset ?? 0)) points; restart the game to apply.").font(.caption)
                Picker("Orientation", selection: Binding(get: {
                    (library.games.first { $0.id == game.id } ?? game).displayOrientation
                }, set: { value in
                    var updated = library.games.first { $0.id == game.id } ?? game
                    updated.orientation = value
                    library.update(updated)
                })) {
                    Text("Rotate automatically").tag("automatic")
                    Text("Portrait · Fit").tag("portrait")
                    Text("Landscape").tag("landscape")
                }
                Text("Portrait fits the complete game without cropping. Controls can use the space around the game.").font(.caption)
            }
            Section(header: Text("Controls & Diagnostics")) {
                Toggle("Virtual controls", isOn: field(game, \.showControls))
                Picker("Reset layout directions", selection: field(game, \.directionKeys)) {
                    Text("Arrow keys").tag("arrows")
                    Text("WASD").tag("wasd")
                }
                TextField("Extra keys for reset layout", text: field(game, \.extraKeys))
                Text("While playing, tap the small ⋯ button for mouse settings and Edit Controls. Drag ⋯ if it covers a game button. The menu starts closed, and layouts save separately for each game.").font(.caption)
                Text("Diagnostic log: Files → Godot Player → GodotPlayerSaves → \(game.id.uuidString) → player.log").font(.caption)
            }
            Section(header: Text("Bundled compatibility components")) {
                Text("Godot 3.6.3 / 4.7.2; Spine (version selected during build); LimboAI 1.8.1 in Godot 4; compiled-script reader v100/v101.").font(.caption)
                Text("Required Android plugins, GDNative, other GDExtensions and .NET remain unsupported unless compatible functionality is built into a later signed player update.").font(.caption).foregroundColor(.secondary)
            }
        }.navigationTitle(game.name)
    }

    private func field<Value>(_ game: Game, _ path: WritableKeyPath<Game, Value>) -> Binding<Value> {
        Binding(get: { (library.games.first { $0.id == game.id } ?? game)[keyPath: path] }, set: { value in
            var updated = library.games.first { $0.id == game.id } ?? game
            updated[keyPath: path] = value
            library.update(updated)
        })
    }
    private func profileField<Value>(_ game: Game, _ path: WritableKeyPath<ControlProfile, Value?>, fallback: Value) -> Binding<Value> {
        Binding(get: { (library.games.first { $0.id == game.id } ?? game).controls[keyPath: path] ?? fallback }, set: { value in
            var profile = (library.games.first { $0.id == game.id } ?? game).controls
            profile[keyPath: path] = value; _ = library.saveControls(profile, visible: game.showControls, for: game.id)
        })
    }

    private func play(_ game: Game) {
        starting = true
        // Validate the directory off the UI thread before starting Godot on main.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try library.prepare(game) }
            DispatchQueue.main.async {
                defer { starting = false }
                do {
                    try result.get()
                    library.journal(game, status: "starting")
                    guard PlayerRuntime.configureScriptKey(try library.scriptKey(game)) else { throw PackError.invalid("Close the app from the app switcher and reopen it before retrying a launch or starting another game.") }
                    PlayerRuntime.configureController(game.controls.controller?.enabled == true)
                    let started: UIViewController? = try PlayerRuntime.startPack(library.packURL(game).path, savePath: library.saveURL(game).path, renderer: game.renderer, engineMajor: Int(game.pack.major), orientation: game.displayOrientation)
                    guard let controller = started else { throw PackError.invalid("The runtime did not create a game view.") }
                    session = GameSession(id: game.id, controller: controller, game: game, aspectRatio: PlayerRuntime.gameAspectRatio())
                } catch { library.journal(game, status: "failed"); library.error = error.localizedDescription }
            }
        }
    }
}

