import SwiftUI

struct SearchToolsPanel: View {
    @ObservedObject var state: GameToolsState
    let canEdit: Bool
    let frozen: [ToolStat]
    let onEdit: (ToolStat) -> Void
    @State private var confirmNew = false

    var body: some View {
        List {
            Section(header: Text("Filters"), footer: Text("Narrow checks only the current candidates. Search Whole Game Again includes variables excluded earlier. Refreshing and reopening tools preserve your baseline. Boolean searches match true/false; flags stored as 0/1 need Number searches.")) {
                TextField("Variable name or path (optional)", text: $state.query)
                    .autocapitalization(.none).disableAutocorrection(true)
                Picker("Type", selection: $state.kind) {
                    Text("Any").tag("any"); Text("Number").tag("number")
                    Text("Boolean").tag("bool"); Text("Text").tag("string")
                }
                Picker("Value", selection: $state.comparison) {
                    Text("Any value").tag("any"); Text("Equals").tag("exact")
                    if state.hasSearch {
                        Text("Changed").tag("changed"); Text("Unchanged").tag("unchanged")
                        Text("Increased (numbers)").tag("increased"); Text("Decreased (numbers)").tag("decreased")
                    }
                }
                if state.comparison == "exact" {
                    if state.kind == "bool" {
                        Picker("Equals", selection: $state.booleanValue) { Text("True").tag("true"); Text("False").tag("false") }
                            .pickerStyle(SegmentedPickerStyle())
                    } else {
                        TextField("Value to match", text: $state.value).autocapitalization(.none).disableAutocorrection(true)
                    }
                }
                Text("Scope: \(state.scopeLabel)").font(.caption).foregroundColor(.secondary)
                if !state.scope.isEmpty {
                    Button("Search Whole Game Instead") { state.scope = ""; state.scopeLabel = "Whole game, including globals" }
                }
                if state.hasSearch {
                    Text("Narrowing pool: \(state.candidateCount) current candidates. Available types: \(state.candidateTypes.map { $0 == "bool" ? "Boolean" : ($0 == "string" ? "Text" : "Number") }.joined(separator: ", "))").font(.caption).foregroundColor(.secondary)
                    if state.needsNewSearch && !state.searching {
                        Text("This search will start from the selected game scope and record a new baseline.").font(.caption).foregroundColor(.orange)
                    }
                }
                if state.searching {
                    ProgressView("Searching: \(state.examined) checked · \(state.workingMatches) matches")
                    Button("Cancel Search") { state.receive(ToolsBridge.send(["action": "cancel_search"])) }
                } else {
                    Button(state.needsNewSearch ? (state.scope.isEmpty ? "Search Whole Game" : "Search This Scope") : "Narrow Results") { search(start: state.needsNewSearch) }
                    if state.hasSearch {
                        Button(state.scope.isEmpty ? "Search Whole Game Again…" : "Search This Scope Again…") { confirmNew = true }
                        Button("Undo Last Narrow (\(state.undoCount))") {
                            state.receive(ToolsBridge.send(["action": "undo_search"]), restoreFilters: true)
                        }.disabled(state.undoCount == 0)
                    }
                }
            }
            Section {
                Text(state.message).font(.caption).foregroundColor(.secondary)
                Toggle("Refresh current values automatically", isOn: $state.autoRefresh)
                Button("Refresh Values") { refresh(page: state.page) }
                Text("Close tools to play, then narrow by Changed, Increased or Decreased. A paused game usually has no new changes.").font(.caption).foregroundColor(.secondary)
                if state.truncated {
                    Label("Incomplete scan: a safety budget or path depth was reached. Use a scene scope or a more specific filter and start a new search.", systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.orange)
                }
            }
            if state.hasSearch || state.searching && !state.rows.isEmpty {
                Section(header: Text(state.discovering ? "\(state.candidateCount) matches so far" : "\(state.candidateCount) candidates")) {
                    pagination
                    ForEach(state.rows) { stat in
                        Button { onEdit(stat) } label: {
                            ToolStatRow(stat: stat, frozen: frozen.contains { $0.id == stat.id })
                        }.disabled(!canEdit || state.searching && !state.discovering)
                    }
                    if state.rows.isEmpty { Text(state.searching ? "Still scanning. Matches will appear here as they are found." : (state.candidateCount == 0 ? "No candidates match. Undo the last narrow or start a new search." : "These candidates are no longer available in this scene.")).foregroundColor(.secondary) }
                    if state.staleCount > 0 { Text("\(state.staleCount) unavailable candidates on this page. Narrow removes stale references.").font(.caption).foregroundColor(.secondary) }
                    if state.pageCount > 1 { pagination }
                }
            }
            Section {
                Button("Undo Last Edit (\(state.editUndoCount))") {
                    let reply = ToolsBridge.send(["action": "undo"])
                    if reply.ok { refresh(page: state.page) } else { state.message = reply.message ?? "Undo failed." }
                }.disabled(!canEdit || state.editUndoCount == 0)
            }
        }.listStyle(InsetGroupedListStyle())
        .confirmationDialog("Replace the current candidates and comparison baseline?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("New Search") { search(start: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your pins and edits are kept. New searches start with Any value or Equals.") }
    }

    private var pagination: some View {
        HStack {
            Button("Previous") { refresh(page: state.page - 1) }.disabled(state.page == 0 || state.searching)
            Spacer()
            Text("Page \(state.page + 1) of \(state.pageCount)").font(.caption).monospacedDigit()
            Spacer()
            Button("Next") { refresh(page: state.page + 1) }.disabled(state.page + 1 >= state.pageCount || state.searching)
        }.buttonStyle(BorderlessButtonStyle())
    }
    private func refresh(page: Int) { state.receive(ToolsBridge.send(["action": "search_results", "page": page])) }
    private func search(start: Bool) {
        let comparison = start && state.comparison != "exact" ? "any" : state.comparison
        if start { state.comparison = comparison }
        state.receive(ToolsBridge.send(["action": start ? "find_numbers" : "refine_numbers", "kind": state.kind,
                                       "comparison": comparison, "value": state.encodedValue,
                                       "search": state.query, "scope": state.scope]))
    }
}

struct ToolStatRow: View {
    let stat: ToolStat
    var frozen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(stat.label).font(.caption).foregroundColor(.secondary).lineLimit(3)
            HStack {
                Text(stat.value).font(.system(.body, design: .monospaced)).foregroundColor(.primary).lineLimit(2)
                Spacer()
                if frozen || stat.frozen == true { Label("Frozen", systemImage: "snowflake").font(.caption).foregroundColor(.blue) }
                Text(stat.type).font(.caption).foregroundColor(.secondary)
            }
            if let previous = stat.previous, previous != stat.value {
                Text("Baseline: \(previous)").font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 3)
    }
}
