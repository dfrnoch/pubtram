import Foundation
import Observation

/// Favorites and history, persisted in UserDefaults.
@MainActor @Observable
final class AppStore {
    private(set) var favoriteRoutes: [SavedRoute] = []
    private(set) var recentRoutes: [SavedRoute] = []
    private(set) var favoriteStops: [Place] = []
    private(set) var recentPlaces: [Place] = []
    var searchOptions = SearchOptions() { didSet { save(searchOptions, "searchOptions") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteRoutes = load("favoriteRoutes") ?? []
        recentRoutes = load("recentRoutes") ?? []
        favoriteStops = load("favoriteStops") ?? []
        recentPlaces = load("recentPlaces") ?? []
        searchOptions = load("searchOptions") ?? SearchOptions()
    }

    // MARK: Routes

    func isFavorite(_ route: SavedRoute) -> Bool {
        favoriteRoutes.contains { $0.id == route.id }
    }

    func toggleFavorite(_ route: SavedRoute) {
        if let i = favoriteRoutes.firstIndex(where: { $0.id == route.id }) {
            favoriteRoutes.remove(at: i)
        } else {
            favoriteRoutes.insert(route, at: 0)
        }
        save(favoriteRoutes, "favoriteRoutes")
    }

    func removeFavoriteRoutes(at offsets: IndexSet) {
        favoriteRoutes.remove(atOffsets: offsets)
        save(favoriteRoutes, "favoriteRoutes")
    }

    func moveFavoriteRoutes(from source: IndexSet, to destination: Int) {
        favoriteRoutes.move(fromOffsets: source, toOffset: destination)
        save(favoriteRoutes, "favoriteRoutes")
    }

    func addRecent(_ route: SavedRoute) {
        recentRoutes.removeAll { $0.id == route.id }
        recentRoutes.insert(route, at: 0)
        recentRoutes = Array(recentRoutes.prefix(10))
        save(recentRoutes, "recentRoutes")
    }

    func removeRecentRoutes(at offsets: IndexSet) {
        recentRoutes.remove(atOffsets: offsets)
        save(recentRoutes, "recentRoutes")
    }

    // MARK: Stops & places

    func isFavorite(stop: Place) -> Bool {
        favoriteStops.contains { $0.id == stop.id }
    }

    func toggleFavorite(stop: Place) {
        if let i = favoriteStops.firstIndex(where: { $0.id == stop.id }) {
            favoriteStops.remove(at: i)
        } else {
            favoriteStops.append(stop)
        }
        save(favoriteStops, "favoriteStops")
    }

    func removeFavoriteStops(at offsets: IndexSet) {
        favoriteStops.remove(atOffsets: offsets)
        save(favoriteStops, "favoriteStops")
    }

    func addRecent(place: Place) {
        guard !place.isCurrentLocation else { return }
        recentPlaces.removeAll { $0.id == place.id }
        recentPlaces.insert(place, at: 0)
        recentPlaces = Array(recentPlaces.prefix(15))
        save(recentPlaces, "recentPlaces")
    }

    // MARK: Persistence

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
