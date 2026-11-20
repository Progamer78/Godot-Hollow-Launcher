import SwiftUI
import UIKit

struct SceneToolsPanel: View {
    @ObservedObject var state: GameToolsState
    let canEdit: Bool
    let onEdit: (ToolStat) -> Void
    @State private var selected: ToolSceneNode?
    private let progressTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section(header: Text("Current scene")) {
                if let scene = state.sceneReply?.currentScene {
                    Text(scene.path).textSelection(.enabled)
                    if !scene.scenePath.isEmpty { Text(scene.scenePath).font(.caption).textSelection(.enabled) }
                } else { Text("The game has not set a current scene.").foregroundColor(.secondary) }
                TextField("Node or script path", text: $state.sceneQuery, onCommit: refresh)
                    .autocapitalization(.none).disableAutocorrection(true)
                Toggle("Hide invisible canvas objects", isOn: $state.visibleOnly).onChange(of: state.visibleOnly) { _ in refresh() }
                Button("Refresh Scene", action: refresh)
                if state.sceneReply?.ok == false { Text(state.sceneReply?.message ?? "Scene unavailable.").foregroundColor(.orange) }
            }
            Section(header: Text("Changes after an action"), footer: Text("Capture, close tools and perform an action, then compare against the original snapshot. Names filter the full scan. Snapshots are independent of Search, cover up to 250,000 accessible values, and stay in memory until replaced or cleared. They do not record executed branches.")) {
                TextField("Variable name or path filter (optional)", text: $state.activityFilter).autocapitalization(.none).disableAutocorrection(true)
                Toggle("Capture current scene only", isOn: $state.activitySceneOnly)
                Button("Capture Snapshot") {
                    state.activityReply = ToolsBridge.send(["action": "capture_activity", "search": state.activityFilter,
                        "scope": state.activitySceneOnly ? (state.sceneReply?.currentScene?.object ?? "") : ""])
                }.disabled(state.activitySceneOnly && state.sceneReply?.currentScene == nil)
                Button("Compare Changes") { state.activityReply = ToolsBridge.send(["action": "compare_activity"]) }.disabled(state.activityReply?.searching == true)
                if state.activityReply != nil { Button("Clear Snapshot & Free Memory") { state.activityReply = nil; _ = ToolsBridge.send(["action": "clear_activity"]) } }
                if let reply = state.activityReply {
                    if reply.ok {
                        Text("\(reply.changedCount ?? 0) changed · \(reply.snapshotCount ?? 0) captured · \(reply.staleCount ?? 0) unavailable").font(.caption)
                        if reply.searching == true { ProgressView(reply.searchDiscovery == true ? "Capturing snapshot…" : "Comparing changes…") }
                        if reply.truncated == true { Text("Snapshot incomplete: scan budget reached.").font(.caption).foregroundColor(.orange) }
                        ForEach(reply.rows ?? []) { stat in
                            Button { onEdit(stat) } label: { ToolStatRow(stat: stat) }.disabled(!canEdit)
                        }
                        pages(reply) { page in state.activityReply = ToolsBridge.send(["action": "activity_results", "page": page]) }
                    } else { Text(reply.message ?? "Capture a snapshot first.").font(.caption).foregroundColor(.orange) }
                }
            }
            Section(header: Text("Live objects"), footer: Text("Open an object to see its paths, callbacks and connected signals, or search its variables. This helps identify relevant buttons, screens and scripts.")) {
                ForEach(state.sceneReply?.nodes ?? []) { node in
                    Button { selected = node } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.name).foregroundColor(.primary)
                            Text(node.path).font(.caption).foregroundColor(.secondary)
                            if !node.scriptPath.isEmpty { Text(node.scriptPath).font(.caption2).foregroundColor(.secondary) }
                        }
                    }
                }
                if let reply = state.sceneReply {
                    Text("\(reply.candidateCount ?? 0) matching objects").font(.caption)
                    if reply.searching == true { ProgressView("Reading scene…") }
                    if reply.truncated == true { Text("The 250,000-node safety budget was reached. Results are incomplete.").font(.caption).foregroundColor(.orange) }
                    pages(reply) { page in state.sceneReply = ToolsBridge.send(["action": "scene_tree", "refresh": false, "page": page]) }
                }
            }
        }.listStyle(InsetGroupedListStyle())
        .onAppear(perform: refresh)
        .onReceive(progressTimer) { _ in
            if state.sceneReply?.searching == true { state.sceneReply = ToolsBridge.send(["action": "continue_scene"]) }
            if state.activityReply?.searching == true { state.activityReply = ToolsBridge.send(["action": "continue_activity"]) }
        }
        .sheet(item: $selected) { node in
            SceneNodeInspector(object: node.object) { chosen in
                state.scope = chosen.object; state.scopeLabel = chosen.path; state.tab = "search"; selected = nil
            }
        }
    }
    private func refresh() {
        state.sceneReply = ToolsBridge.send(["action": "scene_tree", "search": state.sceneQuery, "visibleOnly": state.visibleOnly])
    }
    private func pages(_ reply: ToolReply, change: @escaping (Int) -> Void) -> some View {
        HStack {
            Button("Previous") { change((reply.page ?? 0) - 1) }.disabled((reply.page ?? 0) == 0)
            Spacer()
            Text("Page \((reply.page ?? 0) + 1) of \(reply.pageCount ?? 1)").font(.caption)
            Spacer()
            Button("Next") { change((reply.page ?? 0) + 1) }.disabled((reply.page ?? 0) + 1 >= (reply.pageCount ?? 1))
        }.buttonStyle(BorderlessButtonStyle())
    }
}

private struct SceneNodeInspector: View {
    @State var object: String
    let onScope: (ToolSceneNode) -> Void
    @State private var reply: ToolReply?
    @Environment(\.presentationMode) private var presentation
    var body: some View {
        NavigationView {
            List {
                if let node = reply?.node {
                    Section(header: Text(node.className)) {
                        Text(node.path).textSelection(.enabled)
                        Button("Copy Node Path") { UIPasteboard.general.string = node.path }
                        if !node.scriptPath.isEmpty { Text(node.scriptPath).font(.caption).textSelection(.enabled) }
                        if !node.scenePath.isEmpty { Text(node.scenePath).font(.caption).textSelection(.enabled) }
                        Text("Processing: \(node.processing ? "enabled" : "disabled") · Input callbacks: \(node.inputProcessing ? "enabled" : "disabled")").font(.caption)
                        if let visible = node.visible { Text(visible ? "Visible in scene" : "Hidden in scene").font(.caption) }
                        Button("Use as Search Scope") { onScope(node) }
                    }
                    Section(header: Text("Connected signals"), footer: Text("Connections show target methods, not a trace of conditions being executed. Up to 80 connections are shown. Some games connect signals dynamically.")) {
                        ForEach(Array((reply?.actions ?? []).enumerated()), id: \.offset) { item in
                            Button {
                                object = item.element.targetObject; refresh()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("\(item.element.signal) → \(item.element.method)")
                                    Text(item.element.targetPath).font(.caption).foregroundColor(.secondary)
                                }
                            }.disabled(item.element.targetObject.isEmpty)
                        }
                        if reply?.actions?.isEmpty != false { Text("No connected signals on this object.").foregroundColor(.secondary) }
                    }
                    Section(header: Text("Script")) {
                        if let source = reply?.scriptSource, !source.isEmpty {
                            DisclosureGroup("Read exported script source") {
                                Text(source).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            if reply?.sourceTruncated == true { Text("Showing the first 32 KB.").font(.caption) }
                        } else { Text("This export does not expose readable script source.").font(.caption).foregroundColor(.secondary) }
                    }
                } else { Text(reply?.message ?? "Loading object…").foregroundColor(.secondary) }
            }.navigationTitle("Scene Object")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentation.wrappedValue.dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle()).onAppear(perform: refresh)
    }
    private func refresh() { reply = ToolsBridge.send(["action": "scene_node", "object": object]) }
}
