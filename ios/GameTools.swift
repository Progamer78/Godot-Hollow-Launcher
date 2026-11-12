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
    @State private var tab = "stats"
    @State private var search = "money"
    @State private var rows: [ToolStat] = []
    @State private var selected: ToolStat?
    @State private var selectedPin: SavedCheat?
    @State private var status = ""
    @State private var truncated = false
    @State private var paused = false
    @State private var undoCount = 0
    @State private var code = ""
    @State private var history: [String] = []
    @State private var number = ""
    @State private var comparison = "exact"
    @State private var findRows: [ToolStat] = []
    @State private var findName = ""
    @AppStorage("hollowValueSearchKind") private var findKind = "number"
    @State private var booleanValue = "true"
    @AppStorage("hollowPinnedMonitor") private var showPinnedMonitor = false
    @State private var backedUp = false
    @State private var backupFailed = false
    @State private var speed = 1.0
    @State private var watching = false
    @State private var browsing = false
    @State private var frozenRows: [ToolStat] = []
    private let watchTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Game tools", selection: $tab) {
                    Text("Stats & Cheats").tag("stats")
                    Text("Find").tag("find")
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
                if tab == "stats" { statsView } else if tab == "find" { findView } else if tab == "pins" { pinsView } else { consoleView }
            }
            .navigationTitle("Game Tools")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            GameInput.release()
            let reply = ToolsBridge.send(["action": "pause", "enabled": true])
            paused = reply.ok
            refresh()
            refreshFreezes()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try library.vault.backup(gameID, label: "Automatic: before tools") }
                DispatchQueue.main.async {
                    switch result { case .success: backedUp = true; case .failure(let error): backupFailed = true; status = error.localizedDescription }
                }
            }
        }
        .onReceive(watchTimer) { _ in
            if watching && tab == "stats" { refresh() }
            if tab == "pins" { refreshFreezes() }
        }
        .onChange(of: tab) { _ in refreshFreezes() }
        .onDisappear { _ = ToolsBridge.send(["action": "pause", "enabled": false]) }
        .sheet(item: $selected) { stat in
            StatEditor(stat: stat, gameID: gameID) {
                refreshFreezes()
                if tab == "find" { find(start: false, mode: "any") } else { refresh() }
            }
        }
        .sheet(item:$selectedPin) { pin in
            SavedPinEditor(pin:pin,onSave:{ updated in
                guard var game=library.games.first(where:{$0.id == gameID}), let index=game.savedCheats?.firstIndex(where:{$0.id == updated.id}) else { return }
                game.savedCheats?[index]=updated; library.update(game)
            })
        }
    }

    private var statsView: some View {
        List {
            Section {
                HStack {
                    TextField("Search stats or variable names", text: $search, onCommit: refresh)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Button("Find") { browsing = false; refresh() }
                }
                HStack(spacing: 16) {
                    quickSearch("Money", "money")
                    quickSearch("Gold", "gold")
                    quickSearch("Health", "health")
                    quickSearch("All", "")
                }.buttonStyle(BorderlessButtonStyle())
                Toggle("Watch matching values", isOn: $watching)
                Button(browsing ? "Show Variables" : "Browse Scene Objects") { browsing.toggle(); refresh() }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
            Section(header: Text("Live game variables"), footer: Text("Edits affect the running game. They persist when the game saves. Names and available stats depend on the game.")) {
                if rows.isEmpty {
                    Text("No matching stats found. Try another name such as coins, hp, stamina or level. The console can access other game objects.")
                        .foregroundColor(.secondary)
                }
                ForEach(rows) { stat in
                    Button {
                        if stat.type == "object" { search = stat.label + "."; browsing = false; refresh() }
                        else { selected = stat }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(stat.label).font(.caption).foregroundColor(.secondary).lineLimit(3)
                            HStack {
                                Text(stat.value).font(.system(.body, design: .monospaced)).lineLimit(2).foregroundColor(.primary)
                                Spacer()
                                Text(stat.type).font(.caption).foregroundColor(.secondary)
                                if stat.frozen == true { frozenBadge }
                                Image(systemName: stat.type == "object" ? "chevron.right" : "pencil").foregroundColor(.blue)
                            }
                        }.padding(.vertical, 3)
                    }
                    .disabled(!backedUp)
                }
            }
            if truncated { Text("The scan reached its limit. Use a more specific search; large arrays and deep scene branches may be omitted.").font(.caption).foregroundColor(.secondary) }
            Button("Undo Last Edit (\(undoCount))") {
                let reply = ToolsBridge.send(["action": "undo"])
                refresh()
                status = reply.message ?? ""
            }.disabled(undoCount == 0 || !backedUp)
            Button("Release All Frozen Values") {
                let reply = ToolsBridge.send(["action": "clear_freezes"])
                refresh(); refreshFreezes(); status = reply.ok ? "Freezes released." : "The scene is not ready."
            }
        }.listStyle(InsetGroupedListStyle())
    }

    private var findView: some View {
        List {
            Section(header: Text("Find a value"), footer: Text("Start a search, close tools to change a value in the game, then reopen Find and narrow the results. The optional variable name/path filter is applied before the 150-result limit. Candidates stay for this game session. This searches live script values, not raw memory.")) {
                Picker("Value type", selection: $findKind) { Text("Number").tag("number"); Text("Boolean").tag("bool") }
                    .onChange(of: findKind) { _ in comparison = "exact"; findRows = []; status = "Start a new search for the selected value type." }
                TextField("Variable name or path (optional)", text: $findName).autocapitalization(.none).disableAutocorrection(true)
                if findKind == "bool" {
                    Picker("Value", selection: $booleanValue) { Text("True").tag("true"); Text("False").tag("false") }.pickerStyle(SegmentedPickerStyle())
                } else { TextField("Current value, for example 55", text: $number).keyboardType(.numbersAndPunctuation) }
                Button("Start Exact Search") { find(start: true, mode: "exact") }
                Button(findKind == "bool" ? "Start with Any Boolean" : "Start with Any Number") { find(start: true, mode: "any") }
                Picker("Refine by", selection: $comparison) {
                    Text("Equals selected value").tag("exact"); Text("Changed").tag("changed"); Text("Unchanged").tag("unchanged")
                    if findKind != "bool" { Text("Increased").tag("increased"); Text("Decreased").tag("decreased") }
                }
                Button("Narrow Results") { find(start: false, mode: comparison) }
                Text(status).font(.caption)
            }
            ForEach(findRows) { stat in Button { selected = stat } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stat.label).font(.caption).foregroundColor(.secondary)
                    HStack { Text(stat.type == "bool" ? (stat.value == "true" ? "True" : "False") : stat.value).font(.system(.body, design: .monospaced)); if stat.frozen == true { frozenBadge } }
                }
            }.disabled(!backedUp) }
        }.listStyle(InsetGroupedListStyle())
    }
    private func find(start: Bool, mode: String) {
        let reply = ToolsBridge.send(["action": start ? "find_numbers" : "refine_numbers", "comparison": mode, "value": findKind == "bool" ? booleanValue : number, "kind": findKind, "search": findName])
        findRows = reply.rows ?? []; status = reply.ok ? "\(findRows.count) candidates. Change the value in the game, then narrow again." : (reply.message ?? "Search failed.")
    }
    private var pinsView: some View {
        List {
            Toggle("Pinned value monitor", isOn: $showPinnedMonitor)
            Text("Select up to five pins below. The monitor shows their current live values while playing and never intercepts taps.").font(.caption).foregroundColor(.secondary)
            Text("Pin a stat from its editor. Pins save the variable's scene path, not its temporary instance ID. Apply resolves that path again; ambiguous or missing values are refused.").font(.caption)
            ForEach(library.games.first { $0.id == gameID }?.savedCheats ?? []) { pin in
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
                    })).disabled(pin.monitored != true && (library.games.first { $0.id == gameID }?.savedCheats?.filter { $0.monitored == true }.count ?? 0) >= 5)
                    HStack {
                        Button("Edit Value") { selectedPin=pin }
                        Button("Apply") { apply(pin, frozen: false) }.disabled(!backedUp)
                        Button("Freeze") { apply(pin, frozen: true) }.disabled(!backedUp)
                        Button("Remove") {
                            guard var game = library.games.first(where: { $0.id == gameID }) else { return }
                            game.savedCheats?.removeAll { $0.id == pin.id }; library.update(game)
                        }
                    }.buttonStyle(BorderlessButtonStyle())
                }
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
    private func apply(_ pin: SavedCheat, frozen: Bool) {
        let matches = (ToolsBridge.send(["action": "scan", "search": pin.label]).rows ?? []).filter { $0.label == pin.label && $0.type == pin.type }
        guard matches.count == 1, let target = ToolsBridge.target(matches[0]) else { status = "The pinned variable is missing or ambiguous in the current scene."; return }
        let reply = ToolsBridge.send(["action": frozen ? "freeze" : "edit", "target": target, "value": pin.value])
        status = reply.message ?? (reply.ok ? "Applied" : "Failed")
        refreshFreezes()
    }

    private var frozenBadge: some View { Label("Frozen", systemImage: "snowflake").font(.caption).foregroundColor(.blue) }
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
                Text("Expressions run against the scene root. Use the actual object and property names shown in Stats.").font(.caption)
                Text("Read: get_node('Game').get('money')\nChange: get_node('Game').set('money', 9999)")
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                TextField("Expression", text: $code, onCommit: evaluate)
                    .font(.system(.body, design: .monospaced)).autocapitalization(.none).disableAutocorrection(true)
                Button("Run Expression", action: evaluate).disabled(!backedUp || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Console calls can change game state. Use the stats editor for tracked edits and undo.").font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("Output")) {
                ForEach(Array(history.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.system(.caption, design: .monospaced))
                }
            }
        }.listStyle(InsetGroupedListStyle())
    }

    private func quickSearch(_ title: String, _ value: String) -> some View {
        Button(title) { search = value; browsing = false; refresh() }
    }
    private func refresh() {
        let reply = ToolsBridge.send(["action": browsing ? "objects" : "scan", "search": String(search.prefix(100))])
        if reply.ok {
            rows = reply.rows ?? []; truncated = reply.truncated ?? false; undoCount = reply.undoCount ?? 0
            status = "\(rows.count) matching values · \(reply.visited ?? 0) objects checked"
        } else { rows = []; status = reply.message ?? "The scene is not ready. Try Find again after the game starts." }
    }
    private func evaluate() {
        guard backedUp else { status = "Wait for the save backup to finish before running expressions."; return }
        let expression = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return }
        let reply = ToolsBridge.send(["action": "evaluate", "code": expression])
        history.insert("> \(expression)\n\(reply.ok ? "" : "Error: ")\(reply.message ?? "null")", at: 0)
        history = Array(history.prefix(20))
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
                    Picker("Value",selection:$pin.value) { Text("True").tag("true"); Text("False").tag("false") }
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
