import Foundation
import Observation

/// Favorites, boards and history. Persisted in the shared app group so widgets
/// and Shortcuts see the same data.
@MainActor @Observable
final class AppStore {
    private(set) var favoriteRoutes: [SavedRoute] = []
    private(set) var recentRoutes: [SavedRoute] = []
    private(set) var boards: [SavedBoard] = []
    private(set) var recentPlaces: [Place] = []
    var searchOptions = SearchOptions() { didSet { SharedStore.save(searchOptions, .searchOptions) } }

    init() {
        favoriteRoutes = SharedStore.load(.favoriteRoutes) ?? []
        recentRoutes = SharedStore.load(.recentRoutes) ?? []
        boards = SharedStore.load(.boards) ?? []
        recentPlaces = SharedStore.load(.recentPlaces) ?? []
        searchOptions = SharedStore.load(.searchOptions) ?? SearchOptions()
    }

    // MARK: Favorite routes

    func favorite(matching route: SavedRoute) -> SavedRoute? {
        favoriteRoutes.first { $0.id == route.id }
    }

    func isFavorite(_ route: SavedRoute) -> Bool { favorite(matching: route) != nil }

    func toggleFavorite(_ route: SavedRoute) {
        if let i = favoriteRoutes.firstIndex(where: { $0.id == route.id }) {
            favoriteRoutes.remove(at: i)
        } else {
            favoriteRoutes.append(route)
        }
        routesChanged()
    }

    func rename(_ route: SavedRoute, to name: String) {
        guard let i = favoriteRoutes.firstIndex(where: { $0.id == route.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        favoriteRoutes[i].name = trimmed.isEmpty ? nil : trimmed
        routesChanged()
    }

    func removeFavorite(_ route: SavedRoute) {
        favoriteRoutes.removeAll { $0.id == route.id }
        routesChanged()
    }

    func removeFavoriteRoutes(at offsets: IndexSet) {
        favoriteRoutes.remove(atOffsets: offsets)
        routesChanged()
    }

    func moveFavoriteRoutes(from source: IndexSet, to destination: Int) {
        favoriteRoutes.move(fromOffsets: source, toOffset: destination)
        routesChanged()
    }

    // MARK: Recent routes

    func addRecent(_ route: SavedRoute) {
        recentRoutes.removeAll { $0.id == route.id }
        recentRoutes.insert(SavedRoute(from: route.from, to: route.to), at: 0)
        recentRoutes = Array(recentRoutes.prefix(12))
        SharedStore.save(recentRoutes, .recentRoutes)
    }

    func removeRecent(_ route: SavedRoute) {
        recentRoutes.removeAll { $0.id == route.id }
        SharedStore.save(recentRoutes, .recentRoutes)
    }

    func clearRecentRoutes() {
        recentRoutes = []
        SharedStore.save(recentRoutes, .recentRoutes)
    }

    /// Any known route (favorite or recent) by ID – used by deep links.
    func route(id: String) -> SavedRoute? {
        favoriteRoutes.first { $0.id == id } ?? recentRoutes.first { $0.id == id }
    }

    // MARK: Boards

    func savedBoard(matching board: SavedBoard) -> SavedBoard? {
        boards.first { $0.id == board.id }
    }

    func isSaved(_ board: SavedBoard) -> Bool { savedBoard(matching: board) != nil }

    /// Inserts a new board or replaces `original` with `board`.
    func save(_ board: SavedBoard, replacing original: SavedBoard? = nil) {
        if let original, let i = boards.firstIndex(where: { $0.id == original.id }) {
            boards[i] = board
        } else if let i = boards.firstIndex(where: { $0.id == board.id }) {
            boards[i] = board
        } else {
            boards.append(board)
        }
        boardsChanged()
    }

    func remove(_ board: SavedBoard) {
        boards.removeAll { $0.id == board.id }
        boardsChanged()
    }

    func removeBoards(at offsets: IndexSet) {
        boards.remove(atOffsets: offsets)
        boardsChanged()
    }

    func moveBoards(from source: IndexSet, to destination: Int) {
        boards.move(fromOffsets: source, toOffset: destination)
        boardsChanged()
    }

    func board(id: String) -> SavedBoard? { boards.first { $0.id == id } }

    // MARK: Places

    func addRecent(place: Place) {
        guard !place.isCurrentLocation else { return }
        recentPlaces.removeAll { $0.id == place.id }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(15))
        SharedStore.save(recentPlaces, .recentPlaces)
    }

    // MARK: Side effects

    private func routesChanged() {
        SharedStore.save(favoriteRoutes, .favoriteRoutes)
        SystemIntegration.favoritesChanged(routes: favoriteRoutes, boards: boards)
    }

    private func boardsChanged() {
        SharedStore.save(boards, .boards)
        SystemIntegration.favoritesChanged(routes: favoriteRoutes, boards: boards)
    }
}
