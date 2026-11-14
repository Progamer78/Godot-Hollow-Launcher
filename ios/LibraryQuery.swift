import Foundation

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently played"
    case name = "Name"
    case size = "Size"
    var id: String { rawValue }
}

enum LibraryQuery {
    static func games(_ games: [Game], search: String, collection: String, favoritesOnly: Bool, sort: LibrarySort) -> [Game] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return games.filter { game in
            (!favoritesOnly || game.favorite == true) &&
            (collection.isEmpty || game.collection == collection) &&
            (query.isEmpty || (game.displayName + " " + (game.collection ?? "")).localizedCaseInsensitiveContains(query))
        }.sorted { left, right in
            switch sort {
            case .recent:
                let a = left.lastPlayed ?? .distantPast, b = right.lastPlayed ?? .distantPast
                if a != b { return a > b }
            case .size:
                if left.pack.byteCount != right.pack.byteCount { return left.pack.byteCount > right.pack.byteCount }
            case .name: break
            }
            let order = left.displayName.localizedStandardCompare(right.displayName)
            return order == .orderedSame ? left.id.uuidString < right.id.uuidString : order == .orderedAscending
        }
    }
    static func collections(_ games: [Game]) -> [String] {
        Array(Set(games.compactMap { $0.collection }.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum ImportCancellation {
    static func contains(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError
    }
}
