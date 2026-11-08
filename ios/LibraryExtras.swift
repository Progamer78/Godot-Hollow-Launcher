import SwiftUI
import UniformTypeIdentifiers

struct ShareFiles: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SaveManager: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @State private var snapshots: [SaveSnapshot] = []
    @State private var files: [String] = []
    @State private var status = ""
    @State private var busy = false
    @State private var importing = false
    @State private var shared: URL?
    @State private var sharing = false
    @State private var preview = ""
    @State private var previewing = false
    @State private var restore: SaveSnapshot?
    var body: some View {
        List {
            Section(header: Text("Protect your progress"), footer: Text("Restore/import is available before Play. Each restore/import first backs up the current saves. The five newest automatic backups are retained; manual backups stay until you delete them.")) {
                Button("Create Manual Backup") { work { _ = try library.vault.backup(game.id, label: "Manual backup") } }
                Button("Export Saves as ZIP") {
                    work {
                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("saves-\(UUID().uuidString).zip")
                        try library.vault.export(game.id, to: file)
                        DispatchQueue.main.async { shared = file; sharing = true }
                    }
                }
                Button("Import Saves from ZIP") { importing = true }
                if !status.isEmpty { Text(status).font(.caption) }
            }.disabled(busy)
            Section(header: Text("Backups")) {
                ForEach(snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.label)
                        Text("\(DateFormatter.localizedString(from: snapshot.created, dateStyle: .short, timeStyle: .short)) - \(ByteCountFormatter.string(fromByteCount: snapshot.bytes, countStyle: .file))").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Button("Restore") { restore = snapshot }
                            Spacer()
                            Button("Delete") { work { try library.vault.remove(game.id, snapshot: snapshot) } }.foregroundColor(.red)
                        }.buttonStyle(BorderlessButtonStyle())
                    }
                }
            }.disabled(busy)
            Section(header: Text("Read-only save preview"), footer: Text("Small UTF-8 JSON, CFG, INI, TXT and CSV files can be inspected. Binary saves remain untouched.")) {
                ForEach(files, id: \.self) { name in
                    Button(name) {
                        do { preview = try library.vault.preview(game.id, name: name); previewing = true }
                        catch { status = error.localizedDescription }
                    }
                }
            }
        }.navigationTitle("Saves & Backups")
        .onAppear { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url):
                work {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try library.vault.importArchive(game.id, source: url)
                }
            case .failure(let error): status = error.localizedDescription
            }
        }
        .alert(item: $restore) { snapshot in
            Alert(title: Text("Restore this backup?"), message: Text("The current save folder will be backed up, then replaced."), primaryButton: .destructive(Text("Restore")) { work { try library.vault.restore(game.id, snapshot: snapshot) } }, secondaryButton: .cancel())
        }
        .sheet(isPresented: $sharing, onDismiss: { if let file = shared { try? FileManager.default.removeItem(at: file) }; shared = nil }) { if let file = shared { ShareFiles(items: [file]) } }
        .sheet(isPresented: $previewing) { NavigationView { ScrollView { Text(preview).font(.system(.caption, design: .monospaced)).padding().contextMenu { Button("Copy") { UIPasteboard.general.string = preview } } }.navigationTitle("Save Preview").toolbar { Button("Done") { previewing = false } } } }
    }
    private func reload() {
        do {
            snapshots = try library.vault.snapshots(game.id)
            files = try SafeFiles.children(library.saveURL(game)).map { $0.1 }.filter { ["json", "cfg", "ini", "txt", "csv"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
        } catch { status = error.localizedDescription }
    }
    private func work(_ operation: @escaping () throws -> Void) {
        guard !busy else { return }; busy = true; status = "Working..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                busy = false
                switch result { case .success: status = "Done"; case .failure(let error): status = error.localizedDescription }
                reload()
            }
        }
    }
}

struct StorageManager: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @State private var summary = ""
    var body: some View {
        List {
            Text(summary)
            Button("Clear Rebuildable Shader Cache") {
                do {
                    let gameRoot = library.saveURL(game)
                    let cache = gameRoot.appendingPathComponent("shader_cache")
                    // Only this documented engine cache is disposable. Never
                    // guess that a game's own 'cache' folder can be deleted.
                    if FileManager.default.fileExists(atPath: cache.path) {
                        guard try gameRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                              try cache.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                              cache.resolvingSymlinksInPath().path == gameRoot.resolvingSymlinksInPath().appendingPathComponent("shader_cache").path else { throw PackError.invalid("Unsafe cache link.") }
                        try FileManager.default.removeItem(at: cache)
                    }
                    reload()
                } catch { summary = error.localizedDescription }
            }
            Text("Game assets and saves are retained. Shader caches rebuild when the game starts.").font(.caption)
        }.navigationTitle("Storage").onAppear { reload() }
    }
    private func reload() {
        do {
            let saves = try SafeFiles.children(library.saveURL(game)).reduce(Int64(0)) { $0 + $1.2 }
            let backups = try library.vault.snapshots(game.id).reduce(Int64(0)) { $0 + $1.bytes }
            summary = "Game: \(ByteCountFormatter.string(fromByteCount: Int64(game.pack.byteCount), countStyle: .file))\nSaves and caches: \(ByteCountFormatter.string(fromByteCount: saves, countStyle: .file))\nBackups: \(ByteCountFormatter.string(fromByteCount: backups, countStyle: .file))"
        } catch { summary = error.localizedDescription }
    }
}
