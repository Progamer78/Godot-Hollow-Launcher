import SwiftUI
import UIKit

enum HollowStyle {
    static let brand = Color(red: 0.08, green: 0.43, blue: 0.38)
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.91, blue: 0.77, alpha: 1)
            : UIColor(red: 0.08, green: 0.43, blue: 0.38, alpha: 1)
    })
    static let ink = Color(red: 0.06, green: 0.12, blue: 0.18)
    static let mint = Color(red: 0.55, green: 0.91, blue: 0.77)
    static let name = "Godot Hollow Launcher"
}

struct HollowWelcome: View {
    let count: Int
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 40, weight: .light)).foregroundColor(HollowStyle.mint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(HollowStyle.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(count == 0 ? "A home for your Godot games." : "\(count) \(count == 1 ? "game" : "games"). Ready when you are.")
                    .font(.subheadline).foregroundColor(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [HollowStyle.ink, HollowStyle.brand], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(22)
    }
}

struct HollowGameRow: View {
    let game: Game
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: game.pack.major == 3 ? "sparkles" : "gamecontroller.fill")
                .font(.title2).foregroundColor(HollowStyle.accent)
                .frame(width: 50, height: 58).background(HollowStyle.accent.opacity(0.10)).cornerRadius(14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(game.displayName).font(.headline).lineLimit(2)
                    if game.favorite == true { Image(systemName: "star.fill").font(.caption).foregroundColor(.orange).accessibilityLabel("Favorite") }
                }
                if let collection = game.collection, !collection.isEmpty { Text(collection).font(.caption).foregroundColor(.secondary) }
                Text("Godot \(game.pack.major) · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: game.pack.byteCount), countStyle: .file))")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(.vertical, 6)
        }.accessibilityElement(children: .combine)
    }
}

struct HollowEmptyState: View {
    let filtered: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: filtered ? "magnifyingglass" : "square.and.arrow.down")
                .font(.system(size: 36, weight: .light)).foregroundColor(HollowStyle.accent).accessibilityHidden(true)
            Text(filtered ? "No matching games" : "Your next adventure starts here").font(.headline)
            Text(filtered ? "Try another search or clear your filters." : "Bring a Godot game from Files. Your games and progress stay on your device.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button(action: action) { Label(filtered ? "Clear Filters" : "Import Game", systemImage: filtered ? "line.3.horizontal.decrease.circle" : "plus") }
                .buttonStyle(.borderedProminent).tint(HollowStyle.brand)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 12)
    }
}

struct HollowHelp: View {
    @Environment(\.presentationMode) private var presentation
    @AppStorage("hollowKeepAwake") private var keepAwake = true
    @AppStorage("hollowPerformanceHUD") private var performanceHUD = false
    @AppStorage("hollowHUDCorner") private var hudCorner = "topLeft"
    @AppStorage("hollowPinnedMonitor") private var pinnedMonitor = false
    var body: some View {
        NavigationView {
            List {
                Section { HollowWelcome(count: 0).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section(header: Text("Preferences")) {
                    Toggle("Keep screen awake while playing", isOn: $keepAwake)
                    Toggle("Performance HUD", isOn: $performanceHUD)
                    Toggle("Pinned value monitor", isOn: $pinnedMonitor)
                    if pinnedMonitor { Text("Choose up to five variables in Game Tools → Pins → Show in monitor. Pins appear opposite the performance HUD.").font(.caption).foregroundColor(.secondary) }
                    if performanceHUD {
                        Picker("HUD position", selection: $hudCorner) {
                            Text("Top left").tag("topLeft"); Text("Top right").tag("topRight")
                            Text("Bottom left").tag("bottomLeft"); Text("Bottom right").tag("bottomRight")
                        }
                        Text("FPS, average frame interval, game process time and engine allocation memory. Values update once per second; memory may be unavailable in release builds. CPU time excludes GPU work.").font(.caption).foregroundColor(.secondary)
                    }
                    Text("Large imports also keep the screen awake while Hollow is open.").font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text("Getting started")) {
                    tip("1. Bring a game", "Use Import Game to choose a complete PCK, ZIP, Godot APK or an EXE containing game data. Downloads must finish in Files before importing.", icon: "square.and.arrow.down")
                    tip("2. Make it yours", "Open a game to choose controls, orientation and controller bindings. These settings save separately for every game.", icon: "slider.horizontal.3")
                    tip("3. Play", "Tap Play. During a game, the small ⋯ button opens controls, keyboard, mouse and game tools. Drag it out of the way.", icon: "play.fill")
                }
                Section(header: Text("Import help")) {
                    tip("Encrypted Godot 3 games", "Choose the original Windows x64 EXE and PCK together, or a ZIP containing both. Hollow checks the EXEs inside that ZIP automatically. Only recognized runtime layouts are supported.", icon: "lock.open")
                    tip("Android packages", "Godot APK assets can be imported, but Android plugins cannot run on iOS. Change the APK engine hint only if automatic detection asks you to.", icon: "shippingbox")
                    tip("What can run?", "The bundled engines are Godot 3.6.3 and 4.7.2. Complete GDScript games are the best candidates. .NET, required native plugins, unsupported encryption and missing assets can prevent play.", icon: "checkmark.circle")
                }
                Section(header: Text("Progress & troubleshooting")) {
                    tip("Back up your progress", "Open a game → Saves & Backups. Saves are backed up before launch, replacement and restore. Export a ZIP before deleting a game or removing the app. Backups contain saved files, not an exact-frame save state.", icon: "externaldrive.badge.checkmark")
                    tip("Switching games", "One game runs per app session. Close Hollow from the app switcher and reopen it to return to your library.", icon: "arrow.triangle.2.circlepath")
                    tip("A game won't start?", "Try Safe Launch from the game page. If it still fails, export a support report from that page. It includes selected diagnostics; review it before sharing.", icon: "lifepreserver")
                }
                Section(header: Text("About Hollow")) {
                    Text(HollowStyle.name).font(.headline)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")").foregroundColor(.secondary)
                    Text("Godot 3.6.3 / 4.7.2 · Spine \(Bundle.main.object(forInfoDictionaryKey: "HollowSpineRuntime") as? String ?? "build selection")").font(.caption).foregroundColor(.secondary)
                    Text("An independent launcher for games you supply. Games run locally with bundled Godot engines. No account is needed. Hollow does not upload your library or saves.").font(.subheadline)
                    Text("Imported games run scripts within the app's sandbox. Only import games you trust. Hollow is not affiliated with the Godot Foundation.").font(.caption).foregroundColor(.secondary)
                    NavigationLink("Open-source acknowledgements", destination: HollowNotices())
                }
            }.listStyle(InsetGroupedListStyle()).navigationTitle("Settings & Help")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle()).accentColor(HollowStyle.accent)
    }
    private func tip(_ title: String, _ text: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(text).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                .padding(.vertical, 5)
        } icon: { Image(systemName: icon).foregroundColor(HollowStyle.accent).accessibilityHidden(true) }
    }
}

struct HollowPerformanceHUD: View {
    let reply: ToolReply?
    private func number(_ value: Double?, decimals: Int = 1) -> String {
        guard let value = value, value.isFinite, value >= 0 else { return "—" }
        return String(format: decimals == 0 ? "%.0f" : "%.1f", value)
    }
    private var thermal: String? {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: return "Device warm"
        case .critical: return "Device hot"
        default: return nil
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number(reply?.fps, decimals: 0)) FPS · \(number(reply?.frameMs)) ms").font(.system(.caption, design: .monospaced).bold())
            Text("CPU \(number(reply?.processMs)) ms · Physics \(number(reply?.physicsMs)) ms").font(.system(.caption2, design: .monospaced))
            if let memory = reply?.engineMemoryBytes, memory > 0 {
                Text("Engine memory \(number(memory / 1_048_576)) MB").font(.system(.caption2, design: .monospaced))
            }
            if let thermal = thermal { Text(thermal).font(.caption2).foregroundColor(.yellow) }
        }.padding(10).foregroundColor(.white).background(Color.black.opacity(0.75)).cornerRadius(12)
            .accessibilityElement(children: .combine)
    }
}

struct HollowPinnedHUD: View {
    let rows: [PinnedReadout]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 5) {
                    if row.frozen { Image(systemName: "snowflake").foregroundColor(.cyan).accessibilityLabel("Frozen") }
                    Text("\(row.name): \(row.value)").font(.system(.caption, design: .monospaced)).lineLimit(2)
                }
            }
        }.padding(10).frame(maxWidth: 240, alignment: .leading).foregroundColor(.white)
            .background(Color.black.opacity(0.75)).cornerRadius(12).accessibilityElement(children: .combine)
    }
}

private struct HollowNotices: View {
    private let notices = [("Godot Engine", "GodotEngineNotices"), ("Spine Runtimes", "SpineRuntimeNotices"), ("LimboAI", "LimboAIRuntimeNotices")]
    var body: some View {
        List {
            ForEach(notices.indices, id: \.self) { index in
                let item = notices[index]
                if let text = Bundle.main.object(forInfoDictionaryKey: item.1) as? String {
                    Section(header: Text(item.0)) { Text(text).font(.caption).textSelection(.enabled) }
                }
            }
        }.navigationTitle("Acknowledgements")
    }
}
