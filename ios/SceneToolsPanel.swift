import SwiftUI
import UIKit

struct SceneToolsPanel: View {
    @ObservedObject var state: GameToolsState
    let canEdit: Bool
    let onEdit: (ToolStat) -> Void
    @State private var selected: ToolSceneNode?

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
            Section(header: Text("Changes after an action"), footer: Text("Capture, close tools and perform an action, then compare. This separate snapshot never changes your Search candidates. It checks up to 2,000 accessible script values; it does not record executed branches.")) {
                Button("Capture Snapshot") { state.activityReply = ToolsBridge.send(["action": "capture_activity"]) }
                Button("Compare Changes") { state.activityReply = ToolsBridge.send(["action": "compare_activity"]) }
                if let reply = state.activityReply {
                    if reply.ok {
                        Text("\(reply.changedCount ?? 0) changed · \(reply.snapshotCount ?? 0) captured · \(reply.staleCount ?? 0) unavailable").font(.caption)
                        if reply.truncated == true { Text("Snapshot incomplete: scan budget reached.").font(.caption).foregroundColor(.orange) }
                        ForEach(reply.rows ?? []) { stat in
                            Button { onEdit(stat) } label: { ToolStatRow(stat: stat) }.disabled(!canEdit)
                        }
                        if (reply.changedCount ?? 0) > (reply.rows?.count ?? 0) { Text("Showing the first 200 changes. Use Search to narrow a larger set.").font(.caption) }
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
                if state.sceneReply?.truncated == true { Text("Showing up to 200 objects from the first 600 scene nodes. Filter by path to narrow the list.").font(.caption).foregroundColor(.orange) }
            }
        }.listStyle(InsetGroupedListStyle())
        .onAppear(perform: refresh)
        .sheet(item: $selected) { node in
            SceneNodeInspector(object: node.object) { chosen in
                state.scope = chosen.object; state.scopeLabel = chosen.path; state.tab = "search"; selected = nil
            }
        }
    }
    private func refresh() {
        state.sceneReply = ToolsBridge.send(["action": "scene_tree", "search": state.sceneQuery, "visibleOnly": state.visibleOnly])
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
