import SwiftUI
import Foundation

private enum ToolsBridge {
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
    @Environment(\.presentationMode) private var presentation
    @State private var tab = "stats"
    @State private var search = "money"
    @State private var rows: [ToolStat] = []
    @State private var selected: ToolStat?
    @State private var status = ""
    @State private var truncated = false
    @State private var paused = false
    @State private var undoCount = 0
    @State private var code = ""
    @State private var history: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Game tools", selection: $tab) {
                    Text("Stats & Cheats").tag("stats")
                    Text("Console").tag("console")
                }.pickerStyle(SegmentedPickerStyle()).padding()
                Toggle("Pause game while editing", isOn: Binding(get: { paused }, set: { value in
                    let reply = ToolsBridge.send(["action": "pause", "enabled": value])
                    if reply.ok { paused = value } else { status = reply.message ?? "The scene is not ready." }
                })).padding(.horizontal)
                if tab == "stats" { statsView } else { consoleView }
            }
            .navigationTitle("Game Tools")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            PlayerRuntime.releaseKeys()
            let reply = ToolsBridge.send(["action": "pause", "enabled": true])
            paused = reply.ok
            refresh()
        }
        .onDisappear { _ = ToolsBridge.send(["action": "pause", "enabled": false]) }
        .sheet(item: $selected) { stat in
            StatEditor(stat: stat) { refresh() }
        }
    }

    private var statsView: some View {
        List {
            Section {
                HStack {
                    TextField("Search stats or variable names", text: $search, onCommit: refresh)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Button("Find", action: refresh)
                }
                HStack(spacing: 16) {
                    quickSearch("Money", "money")
                    quickSearch("Gold", "gold")
                    quickSearch("Health", "health")
                    quickSearch("All", "")
                }.buttonStyle(BorderlessButtonStyle())
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundColor(.secondary) }
            Section(header: Text("Live game variables"), footer: Text("Edits affect the running game. They persist when the game saves. Names and available stats depend on the game.")) {
                if rows.isEmpty {
                    Text("No matching stats found. Try another name such as coins, hp, stamina or level. The console can access other game objects.")
                        .foregroundColor(.secondary)
                }
                ForEach(rows) { stat in
                    Button { selected = stat } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(stat.label).font(.caption).foregroundColor(.secondary).lineLimit(3)
                            HStack {
                                Text(stat.value).font(.system(.body, design: .monospaced)).lineLimit(2).foregroundColor(.primary)
                                Spacer()
                                Text(stat.type).font(.caption).foregroundColor(.secondary)
                                Image(systemName: "pencil").foregroundColor(.blue)
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }
            if truncated { Text("The scan reached its limit. Use a more specific search; large arrays and deep scene branches may be omitted.").font(.caption).foregroundColor(.secondary) }
            Button("Undo Last Edit (\(undoCount))") {
                let reply = ToolsBridge.send(["action": "undo"])
                refresh()
                status = reply.message ?? ""
            }.disabled(undoCount == 0)
        }.listStyle(InsetGroupedListStyle())
    }

    private var consoleView: some View {
        List {
            Section(header: Text("Expression console")) {
                Text("Expressions run against the scene root. Use the actual object and property names shown in Stats.").font(.caption)
                Text("Read: get_node('Game').get('money')\nChange: get_node('Game').set('money', 9999)")
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                TextField("Expression", text: $code, onCommit: evaluate)
                    .font(.system(.body, design: .monospaced)).autocapitalization(.none).disableAutocorrection(true)
                Button("Run Expression", action: evaluate).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        Button(title) { search = value; refresh() }
    }
    private func refresh() {
        let reply = ToolsBridge.send(["action": "scan", "search": String(search.prefix(100))])
        if reply.ok {
            rows = reply.rows ?? []; truncated = reply.truncated ?? false; undoCount = reply.undoCount ?? 0
            status = "\(rows.count) matching values · \(reply.visited ?? 0) objects checked"
        } else { rows = []; status = reply.message ?? "The scene is not ready. Try Find again after the game starts." }
    }
    private func evaluate() {
        let expression = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return }
        let reply = ToolsBridge.send(["action": "evaluate", "code": expression])
        history.insert("> \(expression)\n\(reply.ok ? "" : "Error: ")\(reply.message ?? "null")", at: 0)
        history = Array(history.prefix(20))
    }
}

private struct StatEditor: View {
    let stat: ToolStat
    let onApplied: () -> Void
    @Environment(\.presentationMode) private var presentation
    @State private var value: String
    @State private var error: String?
    init(stat: ToolStat, onApplied: @escaping () -> Void) {
        self.stat = stat; self.onApplied = onApplied; _value = State(initialValue: stat.value)
    }
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Variable")) {
                    Text(stat.label).font(.caption)
                    Text("Current: \(stat.value)").font(.system(.body, design: .monospaced))
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
    }
}
