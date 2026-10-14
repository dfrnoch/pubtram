import Foundation
import Observation

enum AppTab: Hashable {
    case connections, departures
}

/// Owns the app's models and routes deep links from widgets, quick actions,
/// Spotlight and Shortcuts.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .connections
    let store: AppStore
    let search: SearchModel
    let boards: BoardsModel

    private init() {
        let store = AppStore()
        self.store = store
        search = SearchModel(store: store)
        boards = BoardsModel()
    }

    func handle(url: URL) {
        if let link = DeepLink(url: url) { handle(link) }
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .route(let id):
            guard let route = store.route(id: id) else { return }
            tab = .connections
            search.apply(route)
        case .board(let id):
            tab = .departures
            boards.selected = store.board(id: id)
        case .departures:
            tab = .departures
        case .search:
            tab = .connections
            search.goHome()
        }
    }
}
