import SwiftUI
import UniformTypeIdentifiers

struct GameFilesManager: View {
    let game: Game
    @EnvironmentObject private var library: GameLibrary
    @State private var importing = false
    @State private var folder = false
    var body: some View {
        Form {
            Section(header: Text("Companion assets")) {
                Text("Keep the same folder layout as the original download: data, bin, maps and other asset folders belong here. These files are separate from your saves.")
                Button("Add Files from ZIP") { folder = false; importing = true }
                Button("Add a Folder") { folder = true; importing = true }
                Text("Folder imports keep the selected folder's name. ZIP imports keep their contents; put data and bin at the ZIP's root.").font(.caption)
            }.disabled(library.importing)
            Section(header: Text("Access in Files")) {
                Text("On My iPhone → Godot Hollow Launcher → GodotPlayerFiles → \(game.id.uuidString)").font(.caption).textSelection(.enabled)
                Text("You can also copy or replace folders there in Files. Fully close Hollow before changing files used by a running game. Native Windows/Android programs and plugins cannot execute on iOS.").font(.caption)
            }
            if library.importing { ProgressView(library.importStatus) }
        }.navigationTitle("Game Files")
        .fileImporter(isPresented: $importing, allowedContentTypes: folder ? [.folder] : [.zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { library.importGameFiles(url, for: game, folder: folder) }
            case .failure(let error): if !ImportCancellation.contains(error) { library.error = error.localizedDescription }
            }
        }
    }
}
