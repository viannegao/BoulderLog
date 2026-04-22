import SwiftData
import Observation

enum LibraryFilter: String, CaseIterable {
    case all = "All"
    case sent = "Sent"
    case projects = "Projects"
}

@Observable
final class LibraryViewModel {
    var filter: LibraryFilter = .all
    var showingImport = false

    func filtered(_ routes: [Route]) -> [Route] {
        switch filter {
        case .all:      return routes
        case .sent:     return routes.filter { $0.isSent }
        case .projects: return routes.filter { !$0.isSent }
        }
    }
}
