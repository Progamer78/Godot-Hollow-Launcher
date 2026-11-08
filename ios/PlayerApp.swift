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

    var body: some View {
        Group {
            if let session = session {
                GameScreen(session: session)
            } else {
                NavigationView {
                    List {
                        if library.games.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundColor(.blue)
                                Text("Your games, offline").font(.headline)
                                Text("Import a complete Godot 3 or 4 PCK to get started.").foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        }
                        ForEach(library.games) { game in
                            NavigationLink(destination: details(game)) {
                                HStack(spacing: 14) {
                                    Image(systemName: "gamecontroller.fill").font(.title2)
                                        .foregroundColor(game.pack.major == 3 ? .orange : .blue)
                                        .frame(width: 44, height: 44)
                                        .background(Color.secondary.opacity(0.08)).cornerRadius(12)
                                    VStack(alignment: .leading, spacing: 4) {
                                    Text(game.name)
                                    Text("Godot \(game.pack.version) · \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
                                        .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }.onDelete { offsets in
                            let selected = offsets.map { library.games[$0] }
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
                            picker = true
                        }.disabled(library.importing || starting)
                    }
                }.navigationViewStyle(StackNavigationViewStyle()).accentColor(.blue)
            }
        }
        .fileImporter(isPresented: $picker, allowedContentTypes: [UTType(filenameExtension: "pck") ?? .data]) { result in
            switch result {
            case .success(let url): library.importPack(url, replacing: replacement)
            case .failure(let error): library.error = error.localizedDescription
            }
        }
        .onOpenURL { url in
            if session == nil { library.importPack(url) }
            else { library.error = "Close the app from the app switcher and reopen it before importing another game." }
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
                Text("Detected engine: \(game.pack.version)")
                Text("Pack format: \(game.pack.format) · \(game.pack.fileCount) files")
                if let versions = game.pack.scriptVersions {
                    Text("Compiled scripts: \(versions.map { String($0) }.joined(separator: ", "))").font(.caption)
                }
                Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
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
                Button("Replace PCK (keep saves)") { replacement = game; picker = true }.disabled(library.importing)
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
                Toggle("Virtual controls", isOn: field(game, \.showControls))
                Picker("Reset layout directions", selection: field(game, \.directionKeys)) {
                    Text("Arrow keys").tag("arrows")
                    Text("WASD").tag("wasd")
                }
                TextField("Extra keys for reset layout", text: field(game, \.extraKeys))
                Text("While playing, tap the small ⋯ button for mouse settings and Edit Controls. Drag ⋯ if it covers a game button. The menu starts closed, and layouts save separately for each game.").font(.caption)
                Text("Diagnostic log: Files → Godot Player → GodotPlayerSaves → \(game.id.uuidString) → player.log").font(.caption)
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

    private func play(_ game: Game) {
        starting = true
        // Validate the directory off the UI thread before starting Godot on main.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try library.prepare(game) }
            DispatchQueue.main.async {
                defer { starting = false }
                do {
                    try result.get()
                    let started: UIViewController? = try PlayerRuntime.startPack(library.packURL(game).path, savePath: library.saveURL(game).path, renderer: game.renderer, engineMajor: Int(game.pack.major), orientation: game.displayOrientation)
                    guard let controller = started else { throw PackError.invalid("The runtime did not create a game view.") }
                    session = GameSession(id: game.id, controller: controller, game: game, aspectRatio: PlayerRuntime.gameAspectRatio())
                } catch { library.error = error.localizedDescription }
            }
        }
    }
}

