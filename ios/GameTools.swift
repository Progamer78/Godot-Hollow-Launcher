import SwiftUI
import Foundation

enum ToolsBridge {
    static func send(_ command: [String: Any]) -> ToolReply {
        do {
            let data = try JSONSerialization.data(withJSONObject: command)
            let json = String(decoding: data, as: UTF8.self)
            let reply = PlayerRuntime.toolsRequest(json)
            return try JSONDecoder().decode(ToolReply.self, from: Data(reply.utf8))
        } catch {
            return ToolReply(ok: false, message: "Could not read game tools: \(error.localizedDescription)", rows: nil, truncated: nil, visited: nil, undoCount: nil)
        }
    }
    static func target(_ stat: ToolStat) -> Any? {
        guard let data = try? JSONEncoder().encode(stat) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

struct GameTools: View {
    let gameID: UUID
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.presentationMode) private var presentation
    @ObservedObject var state: GameToolsState
    @State private var selected: ToolStat?
    @State private var selectedPin: SavedCheat?
    @State private var status = ""
    @State private var paused = false
    @AppStorage("hollowPinnedMonitor") private var showPinnedMonitor = false
    @State private var backedUp = false
    @State private var backupFailed = false
    @State private var speed = 1.0
    @State private var frozenRows: [ToolStat] = []
    private let watchTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Game tools", selection: $state.tab) {
                    Text("Search").tag("search")
                    Text("Scene").tag("scene")
                    Text("Pins").tag("pins")
                    Text("More").tag("console")
                }.pickerStyle(SegmentedPickerStyle()).padding()
                Toggle("Pause game while editing", isOn: Binding(get: { paused }, set: { value in
                    let reply = ToolsBridge.send(["action": "pause", "enabled": value])
                    if reply.ok { paused = value } else { status = reply.message ?? "The scene is not ready." }
                })).padding(.horizontal)
                if !backedUp {
                    Text(backupFailed ? "Save backup failed. Reopen tools after resolving storage/save errors; editing is disabled." : "Backing up saves before editing...").font(.caption).foregroundColor(.orange).padding()
                }
                if state.tab == "search" { SearchToolsPanel(state: state, canEdit: backedUp, frozen: frozenRows, onEdit: { selected = $0 }) }
                else if state.tab == "scene" { SceneToolsPanel(state: state, canEdit: backedUp, onEdit: { selected = $0 }) }
                else if state.tab == "pins" { pinsView } else { consoleView }
            }
            .navigationTitle("Game Tools")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { if state.tab == "pins" { EditButton() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            GameInput.release()
            let reply = ToolsBridge.send(["action": "pause", "enabled": true])
            paused = reply.ok
            refreshSearch()
            refreshFreezes()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try library.vault.backup(gameID, label: "Automatic: before tools") }
                DispatchQueue.main.async {
                    switch result { case .success: backedUp = true; case .failure(let error): backupFailed = true; status = error.localizedDescription }
                }
            }
        }
        .onReceive(watchTimer) { _ in
            if state.autoRefresh && state.tab == "search" && !state.searching { refreshSearch() }
            refreshFreezes()
        }
        .onChange(of: state.tab) { _ in refreshFreezes(); if state.tab == "search" { refreshSearch() } }
        .onDisappear { _ = ToolsBridge.send(["action": "pause", "enabled": false]) }
        .sheet(item: $selected) { stat in
            StatEditor(stat: stat, gameID: gameID) {
                refreshFreezes()
                refreshSearch()
            }
        }
        .sheet(item:$selectedPin) { pin in
            SavedPinEditor(pin:pin,onSave:{ updated in
                guard var game=library.games.first(where:{$0.id == gameID}), let index=game.savedCheats?.firstIndex(where:{$0.id == updated.id}) else { return }
                game.savedCheats?[index]=updated; library.update(game)
            })
        }
    }

    private var pinsView: some View {
        List {
            Toggle("Pinned value monitor", isOn: $showPinnedMonitor)
            Text("\(pins.filter { $0.monitored == true }.count) of 5 selected. Use Edit to drag pins into order, or hold a pin to move it to the top. Select up to five pins below. The monitor shows their current live values while playing and never intercepts taps.").font(.caption).foregroundColor(.secondary)
            Text("Pin a stat from its editor. Pins save the variable's scene path, not its temporary instance ID. Apply resolves that path again; ambiguous or missing values are refused.").font(.caption)
            ForEach(pins) { pin in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pin.name).font(.headline); Text("\(pin.label) = \(pin.value)").font(.caption)
                    if let active = frozenRows.first(where: { $0.label == pin.label && $0.type == pin.type }) {
                        HStack {
                            frozenBadge
                            Text("Held at \(active.value)").font(.caption)
                            Spacer()
                            Button("Unfreeze") { unfreeze(active) }.buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    Toggle("Show in monitor", isOn: Binding(get: { pin.monitored == true }, set: { enabled in
                        guard var game = library.games.first(where: { $0.id == gameID }), let index = game.savedCheats?.firstIndex(where: { $0.id == pin.id }) else { return }
                        game.savedCheats?[index].monitored = enabled; library.update(game)
                        if enabled { showPinnedMonitor = true }
                    })).disabled(pin.monitored != true && pins.filter { $0.monitored == true }.count >= 5)
                    HStack {
                        Button("Edit Value") { selectedPin=pin }
                        Button("Apply") { apply(pin, frozen: false) }.disabled(!backedUp)
                        Button("Freeze") { apply(pin, frozen: true) }.disabled(!backedUp)
                        Button("Remove") {
                            guard var game = library.games.first(where: { $0.id == gameID }) else { return }
                            game.savedCheats?.removeAll { $0.id == pin.id }; library.update(game)
                        }
                    }.buttonStyle(BorderlessButtonStyle())
                }.contextMenu {
                    Button("Move to Top") {
                        guard var game = library.games.first(where: { $0.id == gameID }), let index = game.savedCheats?.firstIndex(where: { $0.id == pin.id }) else { return }
                        game.savedCheats?.remove(at: index); game.savedCheats?.insert(pin, at: 0); library.update(game)
                    }
                }
            }.onMove { offsets, destination in
                guard var game = library.games.first(where: { $0.id == gameID }) else { return }
                var ordered = game.savedCheats ?? []; ordered.move(fromOffsets: offsets, toOffset: destination)
                game.savedCheats = ordered; library.update(game)
            }
            if !frozenRows.isEmpty {
                Section(header: Text("Active freezes (\(frozenRows.count))")) {
                    ForEach(frozenRows) { stat in
                        HStack {
                            VStack(alignment: .leading) { Text(stat.label).font(.caption); Text("Frozen at \(stat.value)").font(.caption).foregroundColor(.secondary) }
                            Spacer()
                            Button("Unfreeze") { unfreeze(stat) }.buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
            }
            Button("Release All Frozen Values") { _ = ToolsBridge.send(["action": "clear_freezes"]); refreshFreezes(); status = "Freezes released." }
            Text(status).font(.caption)
        }.listStyle(InsetGroupedListStyle())
    }
    private var pins: [SavedCheat] { library.games.first { $0.id == gameID }?.savedCheats ?? [] }

    private func apply(_ pin: SavedCheat, frozen: Bool) {
        let matches = (ToolsBridge.send(["action": "scan", "search": pin.label]).rows ?? []).filter { $0.label == pin.label && $0.type == pin.type }
        guard matches.count == 1, let target = ToolsBridge.target(matches[0]) else { status = "The pinned variable is missing or ambiguous in the current scene."; return }
        let reply = ToolsBridge.send(["action": frozen ? "freeze" : "edit", "target": target, "value": pin.value])
        status = reply.message ?? (reply.ok ? "Applied" : "Failed")
        refreshFreezes()
    }

    private var frozenBadge: some View { Label("Frozen", systemImage: "snowflake").font(.caption).foregroundColor(.blue) }
    private func isFrozen(_ stat: ToolStat) -> Bool { frozenRows.contains { $0.id == stat.id && $0.type == stat.type } }
    private func refreshFreezes() { frozenRows = ToolsBridge.send(["action": "freezes"]).rows ?? [] }
    private func unfreeze(_ stat: ToolStat) {
        guard let target = ToolsBridge.target(stat) else { return }
        let reply = ToolsBridge.send(["action": "unfreeze", "target": target])
        status = reply.message ?? ""; refreshFreezes()
    }

    private var consoleView: some View {
        List {
            Section(header: Text("Runtime")) {
                Picker("Frame cap", selection: Binding(get: { library.games.first { $0.id == gameID }?.frameLimit ?? 0 }, set: { fps in
                    let reply = ToolsBridge.send(["action": "options", "fps": fps]); status = reply.message ?? ""
                    if reply.ok, var game = library.games.first(where: { $0.id == gameID }) { game.frameLimit = fps; library.update(game) }
                })) { Text("Game default").tag(0); Text("30 FPS").tag(30); Text("60 FPS").tag(60); Text("120 FPS").tag(120) }
                Text("Game speed: \(String(format: "%.2f", speed))x")
                Slider(value: $speed, in: 0.25...3, step: 0.25, onEditingChanged: { editing in if !editing { status = ToolsBridge.send(["action": "options", "speed": speed]).message ?? "" } })
                Text("Speed affects engine time and may disrupt physics or game logic. Audio playback speed is not changed.").font(.caption)
                Text(status).font(.caption)
            }.disabled(!backedUp)
            Section(header: Text("Expression console")) {
                Text("Expressions run against the scene root. Use the actual object and property names shown in Search or Scene.").font(.caption)
                Text("Read: get_node('Game').get('money')\nChange: get_node('Game').set('money', 9999)")
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                TextField("Expression", text: $state.consoleCode, onCommit: evaluate)
                    .font(.system(.body, design: .monospaced)).autocapitalization(.none).disableAutocorrection(true)
                Button("Run Expression", action: evaluate).disabled(!backedUp || state.consoleCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Console calls can change game state. Use the stats editor for tracked edits and undo.").font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("Output")) {
                ForEach(Array(state.consoleHistory.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.system(.caption, design: .monospaced))
                }
            }
        }.listStyle(InsetGroupedListStyle())
    }

    private func refreshSearch() {
        state.receive(ToolsBridge.send(["action": "search_results", "page": state.page]))
    }
    private func evaluate() {
        guard backedUp else { status = "Wait for the save backup to finish before running expressions."; return }
        let expression = state.consoleCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return }
        let reply = ToolsBridge.send(["action": "evaluate", "code": expression])
        state.consoleHistory.insert("> \(expression)\n\(reply.ok ? "" : "Error: ")\(reply.message ?? "null")", at: 0)
        state.consoleHistory = Array(state.consoleHistory.prefix(20))
    }
}

private struct SavedPinEditor: View {
    @State var pin: SavedCheat
    let onSave: (SavedCheat) -> Void
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            Form {
                TextField("Name",text:$pin.name)
                Text(pin.label).font(.caption)
                if pin.type == "bool" {
                    Picker("Value",selection:$pin.editorValue) { Text("True").tag("true"); Text("False").tag("false") }
                } else { TextField("Pinned value",text:$pin.value).autocapitalization(.none).disableAutocorrection(true) }
                Text("Save changes the reusable value. Apply sends it to the game; Freeze applies and holds it. To change an active freeze, use Freeze again after saving.").font(.caption)
            }.navigationTitle("Edit Pinned Value")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { pin.name=String(pin.name.prefix(80)); pin.value=String(pin.value.prefix(512)); onSave(pin); presentation.wrappedValue.dismiss() } }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct StatEditor: View {
    let stat: ToolStat
    let gameID: UUID
    let onApplied: () -> Void
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.presentationMode) private var presentation
    @State private var value: String
    @State private var error: String?
    @State private var nickname = ""
    @State private var frozen = false
    init(stat: ToolStat, gameID: UUID, onApplied: @escaping () -> Void) {
        self.stat = stat; self.gameID = gameID; self.onApplied = onApplied; _value = State(initialValue: stat.value)
    }
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Variable")) {
                    Text(stat.label).font(.caption)
                    Text("Current: \(stat.value)").font(.system(.body, design: .monospaced))
                    if frozen {
                        Label("Frozen", systemImage: "snowflake").foregroundColor(.blue)
                        Button("Unfreeze This Variable") {
                            guard let target = ToolsBridge.target(stat) else { return }
                            let reply = ToolsBridge.send(["action": "unfreeze", "target": target])
                            if reply.ok { frozen = false; onApplied() } else { error = reply.message }
                        }
                    }
                }
                Section(header: Text("New value")) {
                    if stat.type == "bool" {
                        Picker("Value", selection: $value) { Text("True").tag("true"); Text("False").tag("false") }
                            .pickerStyle(SegmentedPickerStyle())
                    } else {
                        TextField("Value", text: $value).autocapitalization(.none).disableAutocorrection(true)
                    }
                    if let error = error { Text(error).foregroundColor(.red).font(.caption) }
                }
                Section(header: Text("Reusable cheat")) {
                    TextField("Friendly name (optional)", text: $nickname)
                    Button("Pin This Value") {
                        guard var game = library.games.first(where: { $0.id == gameID }) else { return }
                        var pins = game.savedCheats ?? []
                        guard pins.count < 20 else { error = "Remove a pin before adding more than 20."; return }
                        pins.append(SavedCheat(name: nickname.isEmpty ? stat.label : String(nickname.prefix(80)), label: stat.label, type: stat.type, value: String(value.prefix(512))))
                        game.savedCheats = pins; library.update(game); presentation.wrappedValue.dismiss()
                    }
                    Button("Apply and Freeze") {
                        guard let target = ToolsBridge.target(stat) else { return }
                        let reply = ToolsBridge.send(["action": "freeze", "target": target, "value": value])
                        if reply.ok { onApplied(); presentation.wrappedValue.dismiss() } else { error = reply.message }
                    }
                    Text("Freezes run five times per second while the app is active. Missing or type-changed variables are released. Undo releases all freezes.").font(.caption)
                }
            }
            .navigationTitle("Edit Stat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { presentation.wrappedValue.dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let target = ToolsBridge.target(stat) else { error = "Could not encode this stat."; return }
                        let reply = ToolsBridge.send(["action": "edit", "target": target, "value": value])
                        if reply.ok { onApplied(); presentation.wrappedValue.dismiss() }
                        else { error = reply.message ?? "The game rejected this edit." }
                    }
                }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if let target = ToolsBridge.target(stat) { frozen = ToolsBridge.send(["action": "read", "target": target]).rows?.first?.frozen == true }
        }
    }
}
