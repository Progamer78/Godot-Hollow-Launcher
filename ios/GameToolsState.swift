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

    @discardableResult
    func receive(_ reply: ToolReply, restoreFilters: Bool = false) -> Bool {
        guard reply.ok else { message = reply.message ?? "Search could not finish. Your previous results are kept."; return false }
        searching = reply.searching ?? false
        examined = reply.examined ?? 0; workingMatches = reply.workingMatches ?? 0
        page = reply.page ?? 0; pageCount = reply.pageCount ?? 1
        editUndoCount = reply.undoCount ?? 0
        hasSearch = reply.searchStarted ?? false
        rows = reply.rows ?? []
        candidateCount = reply.candidateCount ?? rows.count
        staleCount = reply.staleCount ?? 0
        steps = reply.searchSteps ?? 0
        undoCount = reply.searchUndoCount ?? 0
        truncated = reply.truncated ?? false
        searchedScope = reply.searchScope ?? ""
        if restoreFilters, hasSearch {
            kind = reply.searchKind ?? kind; query = reply.searchFilter ?? query
        }
        message = hasSearch ? "\(candidateCount) candidates · \(steps) refinements" : "Combine filters, then search. Close tools to play; reopen to narrow by what changed."
        return true
    }
}
