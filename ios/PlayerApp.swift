import SwiftUI
import UniformTypeIdentifiers

@main
struct GodotPlayerApp: App {
    @UIApplicationDelegateAdaptor(GDTApplicationDelegate.self) var appDelegate
    @StateObject private var library = GameLibrary()
    var body: some Scene {
        WindowGroup { PlayerRoot().environmentObject(library).accentColor(HollowStyle.accent) }
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
    @State private var showingHelp = false
    @State private var confirmDeletion = false
    @State private var pendingDeletion: [Game] = []
    @State private var collection = ""
    @AppStorage("hollowLibrarySort") private var sortOrder = LibrarySort.recent.rawValue
    @Environment(\.scenePhase) private var phase

    private var visibleGames: [Game] {
        LibraryQuery.games(library.games, search: search, collection: collection, favoritesOnly: favoritesOnly,
                           sort: LibrarySort(rawValue: sortOrder) ?? .recent)
    }
    private var busy: Bool { starting || library.importing }
    private func importGame() {
        replacement = nil; layoutTarget = nil; picker = true
    }
    private func clearFilters() { search = ""; collection = ""; favoritesOnly = false }

    var body: some View {
        Group {
            if let session = session {
                GameScreen(session: session)
            } else {
                libraryScreen
            }
        }
        .sheet(isPresented: $showingHelp) { HollowHelp() }
        .confirmationDialog(pendingDeletion.count == 1 ? "Delete \(pendingDeletion.first?.displayName ?? "game")?" : "Delete these games?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete \(pendingDeletion.count == 1 ? "Game" : "Games")", role: .destructive) {
                let selected = pendingDeletion; pendingDeletion = []
                for game in selected { library.delete(game) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("This removes the imported game, its saves and backups. Export saves from the game page first if you want to keep your progress. The original download is kept.")
        }
        .onChange(of: library.importing) { importing in UIApplication.shared.isIdleTimerDisabled = importing && phase == .active }
        .onChange(of: library.games.count) { _ in
            if !collection.isEmpty && !LibraryQuery.collections(library.games).contains(collection) { collection = "" }
        }
        .onChange(of: phase) { value in if session == nil { UIApplication.shared.isIdleTimerDisabled = library.importing && value == .active } }
        .fileImporter(isPresented: $picker, allowedContentTypes: [.data, .zip], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let target = layoutTarget, replacingGame = replacement
                layoutTarget = nil; replacement = nil
                guard let url = urls.first else { return }
                if let id = target {
                    guard urls.count == 1 else { library.error = "Choose one layout JSON."; return }
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
                } else if urls.count == 1 { library.importPack(url, replacing: replacingGame, engineHint: UInt32(importEngine)) }
                else if urls.count == 2, let pack = urls.first(where: { $0.pathExtension.lowercased() == "pck" }), let exe = urls.first(where: { $0.pathExtension.lowercased() == "exe" }) {
                    library.importPack(pack, companion: exe, replacing: replacingGame, engineHint: UInt32(importEngine))
                } else { library.error = "Choose one game archive, or select its original EXE and PCK together for encrypted Godot 3 games." }
            case .failure(let error): layoutTarget = nil; replacement = nil; if !ImportCancellation.contains(error) { library.error = error.localizedDescription }
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
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: candidate.game.pack.byteCount), countStyle: .file)) -> \(ByteCountFormatter.string(fromByteCount: Int64(clamping: candidate.pack.byteCount), countStyle: .file))")
                    Text("Native descriptors: \((candidate.pack.nativeFiles ?? []).joined(separator: ", "))").font(.caption)
                    if let note = candidate.note { Text(note).font(.caption) }
                    Text("Saves and control layouts keep their identity. A save backup is created first, but the new game version may use an incompatible save format.")
                    if candidate.game.pack.major != candidate.pack.major { Text("The engine family changed. Runtime and renderer overrides will reset to automatic/project defaults.").foregroundColor(.orange) }
                    Button(library.importing ? "Backing up and replacing..." : "Back Up & Replace") { library.confirmImport() }.disabled(library.importing)
                    Button("Cancel") { library.cancelImport() }.disabled(library.importing)
                }.navigationTitle("Review Game Update")
            }.navigationViewStyle(StackNavigationViewStyle()).interactiveDismissDisabled(library.importing)
        }
        .alert(isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            let message = library.error ?? "Please try again."
            return Alert(title: Text("Hollow couldn't finish that"), message: Text(message), primaryButton: .default(Text("Copy Details")) { UIPasteboard.general.string = message }, secondaryButton: .cancel(Text("Close")))
        }
    }

    private var libraryScreen: some View {
        NavigationView {
            List {
                Section {
                    HollowWelcome(count: library.games.count).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if let notice = library.notice {
                    Section {
                        Label(notice, systemImage: "info.circle").font(.subheadline)
                        Button("Dismiss") { library.notice = nil }
                    }
                }
                if library.readOnly {
                    Section { Label("Library changes are disabled to protect your files. Keep the app installed and preserve its files before troubleshooting.", systemImage: "exclamationmark.shield").font(.subheadline) }
                }
                if !library.games.isEmpty {
                    Section {
                        Toggle(isOn: $favoritesOnly) { Label("Favorites", systemImage: "star") }
                        HStack {
                            Picker("Sort", selection: $sortOrder) {
                                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        }
                        if !LibraryQuery.collections(library.games).isEmpty {
                            Picker("Collection", selection: $collection) {
                                Text("All games").tag("")
                                ForEach(LibraryQuery.collections(library.games), id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                }
                Section(header: Text(visibleGames.isEmpty ? "" : "Your games")) {
                    if visibleGames.isEmpty {
                        HollowEmptyState(filtered: !library.games.isEmpty) {
                            if library.games.isEmpty { importGame() } else { clearFilters() }
                        }.disabled(busy || library.readOnly)
                    }
                    ForEach(visibleGames) { game in
                        NavigationLink(destination: details(game)) { HollowGameRow(game: game) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDeletion = [game]; confirmDeletion = true } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { var value = game; value.favorite = game.favorite != true; library.update(value) } label: {
                                    Label(game.favorite == true ? "Unfavorite" : "Favorite", systemImage: game.favorite == true ? "star.slash" : "star")
                                }.tint(HollowStyle.brand)
                            }
                    }.onDelete { offsets in
                        pendingDeletion = offsets.map { visibleGames[$0] }; confirmDeletion = true
                    }
                }
                Section {
                    Button { showingHelp = true } label: { Label("Settings & Help", systemImage: "gearshape") }
                } footer: {
                    Text("PCK · ZIP · APK · EXE. To switch games, close Hollow from the app switcher and reopen it.")
                }
            }.listStyle(InsetGroupedListStyle())
            .searchable(text: $search, prompt: "Games or collections")
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingHelp = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings, help and app information")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: importGame) { Label("Import Game", systemImage: "plus") }
                        Picker("APK engine hint", selection: $importEngine) {
                            Text("Detect automatically").tag("automatic")
                            Text("Godot 3 assets").tag("3")
                            Text("Godot 4 assets").tag("4")
                        }
                    } label: { Label("Import", systemImage: "plus") }.disabled(busy || library.readOnly)
                }
            }
            .overlay(alignment: .bottom) {
                if busy {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(starting ? "Preparing your game…" : library.importStatus).font(.subheadline.bold())
                            Text("Large games can take a few minutes. Keep Hollow open.").font(.caption).foregroundColor(.secondary)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial).cornerRadius(16).padding()
                        .accessibilityElement(children: .combine)
                }
            }
            .disabled(starting)
        }.navigationViewStyle(StackNavigationViewStyle()).accentColor(HollowStyle.accent)
    }

    private func details(_ original: Game) -> some View {
        let game = library.games.first { $0.id == original.id } ?? original
        return Form {
            Section {
                HollowGameRow(game: game)
                Button { play(game) } label: { Label(starting ? "Preparing…" : "Play Game", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).tint(HollowStyle.brand)
                    .disabled(busy || RuntimeSelection.problem(for: game) != nil)
            }
            Section(header: Text("Your game")) {
                TextField("Name", text: field(game, \.name)).accessibilityLabel("Game name")
                Toggle("Favorite", isOn: Binding(get: { game.favorite == true }, set: { value in var copy = game; copy.favorite = value; library.update(copy) }))
                TextField("Collection", text: Binding(get: { game.collection ?? "" }, set: { value in var copy = game; copy.collection = String(value.prefix(60)); library.update(copy) }))
                TextField("Your notes", text: Binding(get: { game.notes ?? "" }, set: { value in var copy = game; copy.notes = String(value.prefix(2000)); library.update(copy) }))
                Text("Detected engine: \(game.pack.version)")
                Text("Pack format: \(game.pack.format) · \(game.pack.fileCount) files")
                if let versions = game.pack.scriptVersions {
                    Text("Compiled scripts: \(versions.map { String($0) }.joined(separator: ", "))").font(.caption)
                }
                Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: game.pack.byteCount), countStyle: .file))")
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
                Button("Replace PCK (keep saves)") { layoutTarget = nil; replacement = game; picker = true }.disabled(library.importing)
                Button("Safe Launch") {
                    var safe = game; safe.renderer = game.pack.major == 3 ? "gles2" : "gl_compatibility"; safe.showControls = false; safe.frameLimit = 30; var controls = safe.controls; controls.controller?.enabled = false; controls.mouseEnabled = false; safe.controlProfile = controls
                    play(safe)
                }.disabled(starting || library.importing || RuntimeSelection.problem(for: game) != nil)
                Text("Safe Launch uses OpenGL, a 30 FPS cap, hidden virtual controls and disabled controller remapping for this session. It cannot supply missing classes or unsupported encryption.").font(.caption)
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
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Hollow-layout-\(UUID().uuidString).json")
                        try JSONEncoder().encode(game.controls).write(to: file, options: .atomic)
                        sharedReport = file; sharingReport = true
                    } catch { library.error = error.localizedDescription }
                }
                Slider(value: profileField(game, \.opacity, fallback: 0.85), in: 0.2...1).accessibilityLabel("Control opacity")
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
                Slider(value: Binding(get: { game.displayInset ?? 0 }, set: { value in var copy = game; copy.displayInset = value; library.update(copy) }), in: 0...48, step: 2).accessibilityLabel("Game margin")
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
                Text("Diagnostic log: Files → Godot Hollow Launcher → GodotPlayerSaves → \(game.id.uuidString) → player.log").font(.caption)
            }
            Section(header: Text("Bundled compatibility components")) {
                Text("Godot 3.6.3 / 4.7.2; Spine (version selected during build); LimboAI 1.8.1 in Godot 4; compiled-script reader v100/v101.").font(.caption)
                Text("Required Android plugins, GDNative, other GDExtensions and .NET remain unsupported unless compatible functionality is built into a later signed player update.").font(.caption).foregroundColor(.secondary)
            }
            Section {
                Button(role: .destructive) { pendingDeletion = [game]; confirmDeletion = true } label: { Label("Delete Game", systemImage: "trash") }.disabled(busy || library.readOnly)
            }
        }.navigationTitle(game.displayName)
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
            profile[keyPath: path] = value; _ = library.saveControls(profile, visible: (library.games.first { $0.id == game.id } ?? game).showControls, for: game.id)
        })
    }

    private func play(_ game: Game) {
        guard !busy, !library.readOnly else { return }
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

