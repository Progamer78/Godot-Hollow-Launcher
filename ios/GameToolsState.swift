import Foundation
import Combine

// Owned by the running GameScreen, not by its temporary tools sheet. Targets
// remain valid only in this process, so this state is never saved to disk.
final class GameToolsState: ObservableObject {
    @Published var tab = "search"
    @Published var query = ""
    @Published var kind = "any"
    @Published var comparison = "any"
    @Published var value = ""
    @Published var booleanValue = "true"
    @Published var rows: [ToolStat] = []
    @Published var searching = false
    @Published var discovering = false
    @Published var examined = 0
    @Published var workingMatches = 0
    @Published var page = 0
    @Published var pageCount = 1
    @Published var editUndoCount = 0
    @Published var hasSearch = false
    @Published var candidateCount = 0
    @Published var staleCount = 0
    @Published var steps = 0
    @Published var undoCount = 0
    @Published var truncated = false
    @Published var autoRefresh = false
    @Published var message = ""
    @Published var scope = ""
    @Published var scopeLabel = "Whole game, including globals"
    @Published var searchedScope = ""
    @Published var consoleCode = ""
    @Published var consoleHistory: [String] = []
    @Published var sceneQuery = ""
    @Published var visibleOnly = true
    @Published var sceneReply: ToolReply?
    @Published var activityReply: ToolReply?

    var encodedValue: String { kind == "bool" ? booleanValue : value }
    var scopeChanged: Bool { hasSearch && scope != searchedScope }

    private var searchSender: (([String: Any]) -> ToolReply)?
    private var searchActive = false
    private var scheduled = false
    private var searchGeneration = 0
    private var lastProgress = Date.distantPast

    // Yield to UIKit between bounded native batches, without the old 200 ms
    // heartbeat delay. Publish progress at 10 Hz, rather than redrawing the
    // whole sheet for every batch. Nothing is scheduled while idle/backgrounded.
    func setSearchActive(_ active: Bool, send: (([String: Any]) -> ToolReply)? = nil) {
        if let send = send { searchSender = send }
        searchActive = active
        if !active { invalidateScheduledSearch() }
        else { scheduleSearchBatch() }
    }

    private func invalidateScheduledSearch() {
        searchGeneration += 1
        scheduled = false
    }

    private func scheduleSearchBatch() {
        guard searchActive, searching, !scheduled, searchSender != nil else { return }
        scheduled = true
        let generation = searchGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
            guard let self = self, self.searchGeneration == generation else { return }
            self.scheduled = false
            guard self.searchActive, self.searching, let send = self.searchSender else { return }
            let publish = Date().timeIntervalSince(self.lastProgress) >= 0.1
            let reply = send(["action": "continue_search", "progressOnly": !publish])
            if !reply.ok {
                self.message = reply.message ?? "Search stopped. Cancel it to keep your previous results."
                return
            }
            if publish || reply.searching != true { self.receive(reply) }
            self.scheduleSearchBatch()
        }
    }

    @discardableResult
    func receive(_ reply: ToolReply, restoreFilters: Bool = false) -> Bool {
        guard reply.ok else { message = reply.message ?? "Search could not finish. Your previous results are kept."; return false }
        searching = reply.searching ?? false
        discovering = reply.searchDiscovery ?? false
        if !searching { invalidateScheduledSearch() }
        lastProgress = Date()
        examined = reply.examined ?? 0; workingMatches = reply.workingMatches ?? 0
        page = reply.page ?? 0; pageCount = reply.pageCount ?? 1
        editUndoCount = reply.undoCount ?? 0
        hasSearch = reply.searchStarted ?? false
        // Progress-only responses intentionally omit rows. Keep the preview
        // until the next published page or the completed result replaces it.
        if let updated = reply.rows { rows = updated }
        candidateCount = reply.candidateCount ?? rows.count
        staleCount = reply.staleCount ?? 0
        steps = reply.searchSteps ?? 0
        undoCount = reply.searchUndoCount ?? 0
        truncated = reply.truncated ?? false
        searchedScope = reply.searchScope ?? ""
        if restoreFilters, hasSearch {
            kind = reply.searchKind ?? kind; query = reply.searchFilter ?? query
        }
        message = searching ? (discovering ? "Scanning · \(workingMatches) matches so far. You can open a matching variable while discovery continues." : "Narrowing · \(examined) checked · \(workingMatches) matches so far.") :
            (hasSearch ? "\(candidateCount) candidates · \(steps) refinements" : "Combine filters, then search. Close tools to play; reopen to narrow by what changed.")
        scheduleSearchBatch()
        return true
    }
}
