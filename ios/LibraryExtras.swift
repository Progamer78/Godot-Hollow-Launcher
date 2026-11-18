import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    @State private var requestedAction: SaveAction?
    @State private var editingFile: EditableSave?
    var body: some View {
        List {
            Section(header: Text("Protect your progress"), footer: Text("Restore/import is available before Play. Each restore/import first backs up the current saves. The five newest automatic backups are retained; manual backups stay until you delete them.")) {
                if busy { ProgressView("Working with your saves…") }
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
                if snapshots.isEmpty { Text("No backups yet. Create one here, or play a game to create an automatic backup.").font(.subheadline).foregroundColor(.secondary) }
                ForEach(snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.label)
                        Text("\(DateFormatter.localizedString(from: snapshot.created, dateStyle: .short, timeStyle: .short)) - \(ByteCountFormatter.string(fromByteCount: snapshot.bytes, countStyle: .file))").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Button("Restore") { requestedAction = .restore(snapshot) }
                            Spacer()
                            Button("Delete") { requestedAction = .delete(snapshot) }.foregroundColor(.red)
                        }.buttonStyle(BorderlessButtonStyle())
                    }
                }
            }.disabled(busy)
            Section(header: Text("Browse & edit saves"), footer: Text("UTF-8 JSON, CFG, INI, TXT and CSV files up to 256 KB can be edited before Play. A backup is created before each edit. Binary or encrypted saves remain read-only.")) {
                if files.isEmpty { Text("No editable text saves yet. Save your progress inside the game first.").foregroundColor(.secondary).font(.subheadline) }
                ForEach(files, id: \.self) { name in
                    Button {
                        do { editingFile = EditableSave(name: name, text: try library.vault.preview(game.id, name: name)) }
                        catch { status = error.localizedDescription }
                    } label: { Label(name, systemImage: "doc.text").font(.subheadline) }
                }
            }.disabled(busy)
        }.navigationTitle("Saves & Backups")
        .onAppear { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            switch result {
            case .success(let url):
                requestedAction = .importZip(url)
            case .failure(let error): if !ImportCancellation.contains(error) { status = error.localizedDescription }
            }
        }
        .alert(item: $requestedAction) { action in
            switch action {
            case .restore(let snapshot):
                return Alert(title: Text("Restore this backup?"), message: Text("Your current saves will be backed up, then replaced."), primaryButton: .destructive(Text("Back Up & Restore")) { work { try library.vault.restore(game.id, snapshot: snapshot) } }, secondaryButton: .cancel())
            case .delete(let snapshot):
                return Alert(title: Text("Delete this backup?"), message: Text("Only this backup is removed. Your current game saves are kept."), primaryButton: .destructive(Text("Delete Backup")) { work { try library.vault.remove(game.id, snapshot: snapshot) } }, secondaryButton: .cancel())
            case .importZip(let url):
                return Alert(title: Text("Replace current saves?"), message: Text("Current saves will be backed up, then replaced by the ZIP contents. Use saves from the same game version."), primaryButton: .destructive(Text("Back Up & Import")) {
                    work {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        try library.vault.importArchive(game.id, source: url)
                    }
                }, secondaryButton: .cancel())
            }
        }
        .sheet(isPresented: $sharing, onDismiss: { if let file = shared { try? FileManager.default.removeItem(at: file) }; shared = nil }) { if let file = shared { ShareFiles(items: [file]) } }
        .sheet(item: $editingFile, onDismiss: reload) { file in SaveTextEditor(game: game, file: file) }
    }
    private func reload() {
        work {}
    }
    private func work(_ operation: @escaping () throws -> Void) {
        guard !busy else { return }; busy = true; status = "Working..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> ([SaveSnapshot], [String]) in
                try operation()
                let snapshots = try library.vault.snapshots(game.id)
                let files = try SafeFiles.children(library.saveURL(game)).filter { $0.2 <= 256 * 1024 }.map { $0.1 }.filter { ["json", "cfg", "ini", "txt", "csv"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
                return (snapshots, files)
            }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success(let contents): snapshots = contents.0; files = contents.1; status = "Ready"
                case .failure(let error): status = error.localizedDescription; library.error = error.localizedDescription
                }
            }
        }
    }
}

private enum SaveAction: Identifiable {
    case restore(SaveSnapshot), delete(SaveSnapshot), importZip(URL)
    var id: String {
        switch self {
        case .restore(let snapshot): return "restore-" + snapshot.id.uuidString
        case .delete(let snapshot): return "delete-" + snapshot.id.uuidString
        case .importZip(let url): return "import-" + url.absoluteString
        }
    }
}

private struct EditableSave: Identifiable {
    let id = UUID()
    let name: String
    let text: String
}

private struct SaveTextEditor: View {
    let game: Game
    let file: EditableSave
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.presentationMode) private var presentation
    @State private var text: String
    @State private var original: String
    @State private var saving = false
    @State private var message = ""
    @State private var error: String?
    @State private var discarding = false
    init(game: Game, file: EditableSave) {
        self.game = game; self.file = file
        _text = State(initialValue: file.text); _original = State(initialValue: file.text)
    }
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("A backup is created before saving", systemImage: "shield.lefthalf.filled").font(.subheadline)
                    Text("JSON syntax is checked. Other formats keep the text you enter; the game decides which values it accepts.").font(.caption).foregroundColor(.secondary)
                    if file.name.lowercased().hasSuffix(".json") { Button("Format JSON") { formatJSON() }.font(.subheadline) }
                    if !message.isEmpty { Text(message).font(.caption).foregroundColor(HollowStyle.accent) }
                }.padding()
                Divider()
                SaveSourceEditor(text: $text, editable: !saving)
                if saving { ProgressView("Backing up and saving…").padding() }
            }.navigationTitle((file.name as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { if text != original { discarding = true } else { presentation.wrappedValue.dismiss() } }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(saving || text == original) }
            }
        }.navigationViewStyle(StackNavigationViewStyle()).interactiveDismissDisabled(saving || text != original)
        .alert(isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Alert(title: Text("Couldn't save this file"), message: Text(error ?? ""), dismissButton: .default(Text("OK"))) }
        .confirmationDialog("Discard unsaved changes?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { presentation.wrappedValue.dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }
    private func formatJSON() {
        do { text = try SaveTextFormat.json(text); message = "Formatted for reading. Tap Save to keep these changes." }
        catch { self.error = "This file isn't valid JSON yet. Check quotes, commas and brackets." }
    }
    private func save() {
        guard !saving else { return }
        saving = true
        let edited = text, expected = original
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try library.vault.edit(game.id, name: file.name, original: expected, text: edited) }
            DispatchQueue.main.async {
                saving = false
                switch result {
                case .success: original = edited; message = "Saved. Your previous file is in Backups."
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }
}

private struct SaveSourceEditor: UIViewRepresentable {
    @Binding var text: String
    let editable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFontMetrics.default.scaledFont(for: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear; view.textColor = .label
        view.autocapitalizationType = .none; view.autocorrectionType = .no; view.spellCheckingType = .no
        view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.accessibilityLabel = "Save file contents"
        if #available(iOS 16.0, *) { view.isFindInteractionEnabled = true }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.isEditable = editable
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SaveSourceEditor
        init(_ parent: SaveSourceEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text ?? "" }
    }
}

struct StorageManager: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @State private var summary = ""
    @State private var busy = false
    var body: some View {
        List {
            if busy { ProgressView("Checking storage…") }
            Text(summary)
            Button("Clear Rebuildable Shader Cache") {
                busy = true
                DispatchQueue.global(qos: .userInitiated).async {
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
                    DispatchQueue.main.async { busy = false; reload() }
                  } catch { DispatchQueue.main.async { busy = false; summary = error.localizedDescription } }
                }
            }
            .disabled(busy)
            Text("Game assets and saves are retained. Shader caches rebuild when the game starts.").font(.caption)
        }.navigationTitle("Storage").onAppear { reload() }
    }
    private func reload() {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let saves = try SafeFiles.children(library.saveURL(game)).reduce(Int64(0)) { $0 + $1.2 }
            let backups = try library.vault.snapshots(game.id).reduce(Int64(0)) { $0 + $1.bytes }
            let result = "Game: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: game.pack.byteCount), countStyle: .file))\nSaves and caches: \(ByteCountFormatter.string(fromByteCount: saves, countStyle: .file))\nBackups: \(ByteCountFormatter.string(fromByteCount: backups, countStyle: .file))"
            DispatchQueue.main.async { summary = result; busy = false }
          } catch { DispatchQueue.main.async { summary = error.localizedDescription; busy = false } }
        }
    }
}
