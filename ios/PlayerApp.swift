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

private struct GameSession: Identifiable {
    let id: UUID
    let controller: UIViewController
    let game: Game
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
                            Text("Import a complete Godot 4 PCK to play offline.")
                        }
                        ForEach(library.games) { game in
                            NavigationLink(destination: details(game)) {
                                VStack(alignment: .leading) {
                                    Text(game.name)
                                    Text("Godot \(game.pack.version) · \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }.onDelete { offsets in
                            let selected = offsets.map { library.games[$0] }
                            for game in selected { library.delete(game) }
                        }
                        Section(footer: Text("One game per app process. To return to the library, close the app from the app switcher and reopen it. Only import games you trust; scripts share the app's iOS sandbox.")) {
                            Text("Runtime: Godot 4.7.2 · ARM64")
                        }
                    }
                    .navigationTitle("Godot Player")
                    .toolbar {
                        Button(library.importing ? "Importing…" : "Import Game") {
                            replacement = nil
                            picker = true
                        }.disabled(library.importing || starting)
                    }
                }.navigationViewStyle(StackNavigationViewStyle())
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
                Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))")
                Text(RuntimeSelection.problem(for: game) ?? "Candidate for Godot 4.7.2. Execution compatibility is checked by the engine.")
                Button(starting ? "Starting…" : "Play") { play(game) }
                    .disabled(starting || library.importing || RuntimeSelection.problem(for: game) != nil)
                Button("Replace PCK (keep saves)") { replacement = game; picker = true }.disabled(library.importing)
            }
            Section(header: Text("Launch settings")) {
                Picker("Runtime override", selection: field(game, \.runtime)) {
                    Text("Automatic").tag("automatic")
                    Text("Godot 4.7.2").tag("godot4")
                    Text("Godot 3 (unavailable)").tag("godot3")
                }
                Picker("Renderer", selection: field(game, \.renderer)) {
                    Text("Project default").tag("project")
                    Text("Mobile / Metal").tag("mobile")
                    Text("Compatibility / OpenGL").tag("gl_compatibility")
                }
                Toggle("Virtual controls", isOn: field(game, \.showControls))
                Picker("Directions", selection: field(game, \.directionKeys)) {
                    Text("Arrow keys").tag("arrows")
                    Text("WASD").tag("wasd")
                }
                TextField("Additional keys, comma separated", text: field(game, \.extraKeys))
                Text("Extra keys: single letters, Space, Shift, Control, Tab, Enter, Escape. Touch, physical keyboards, and supported Bluetooth controllers use Godot's native input.").font(.caption)
                Text("Project scaling and orientation are preserved where iOS permits. Diagnostic log: Files → Godot Player → GodotPlayerSaves → \(game.id.uuidString) → player.log").font(.caption)
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
                    let started: UIViewController? = try PlayerRuntime.startPack(library.packURL(game).path, savePath: library.saveURL(game).path, renderer: game.renderer)
                    guard let controller = started else { throw PackError.invalid("The runtime did not create a game view.") }
                    session = GameSession(id: game.id, controller: controller, game: game)
                } catch { library.error = error.localizedDescription }
            }
        }
    }
}

private struct EngineView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private struct GameScreen: View {
    let session: GameSession
    @Environment(\.scenePhase) private var phase
    @State private var controls = true
    var body: some View {
        ZStack {
            EngineView(controller: session.controller).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button(controls ? "Hide Controls" : "Show Controls") {
                        PlayerRuntime.releaseKeys()
                        controls.toggle()
                    }.padding(8).background(Color.black.opacity(0.65)).foregroundColor(.white).cornerRadius(8)
                }
                Spacer()
                if controls { controlsView }
            }.padding()
        }
        .onAppear { controls = session.game.showControls }
        .onChange(of: phase) { if $0 != .active { PlayerRuntime.releaseKeys() } }
    }
    private var controlsView: some View {
        let keys = session.game.directionKeys == "wasd" ? ["W", "A", "S", "D"] : ["Up", "Left", "Down", "Right"]
        let extra = Array(Set(session.game.extraKeys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })).sorted().prefix(6)
        return HStack(alignment: .bottom) {
            VStack(spacing: 4) {
                HoldKey(title: "↑", key: keys[0])
                HStack(spacing: 4) {
                    HoldKey(title: "←", key: keys[1]); HoldKey(title: "↓", key: keys[2]); HoldKey(title: "→", key: keys[3])
                }
            }
            Spacer()
            VStack {
                HStack { ForEach(Array(extra), id: \.self) { HoldKey(title: $0, key: $0) } }
                HStack { HoldKey(title: "Cancel", key: "Escape"); HoldKey(title: "Confirm", key: "Enter") }
            }
        }
    }
}

private final class KeyButton: UIButton {
    var mappedKey = ""
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        PlayerRuntime.setKey(mappedKey, pressed: true)
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { PlayerRuntime.setKey(mappedKey, pressed: false) }
    override func cancelTracking(with event: UIEvent?) { PlayerRuntime.setKey(mappedKey, pressed: false) }
}

private struct HoldKey: View {
    let title: String
    let key: String
    var body: some View { KeySurface(title: title, key: key).frame(width: 64, height: 48) }
}

private struct KeySurface: UIViewRepresentable {
    let title: String
    let key: String
    func makeUIView(context: Context) -> KeyButton {
        let button = KeyButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 10
        button.accessibilityLabel = key
        return button
    }
    func updateUIView(_ button: KeyButton, context: Context) { button.mappedKey = key; button.setTitle(title, for: .normal) }
}
