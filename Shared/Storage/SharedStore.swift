import CoreLocation
import Foundation

/// Persistence shared between the app, widgets and intents (via the app group).
enum SharedStore {
    static let appGroup = "group.cz.lynx.pubtram"

    enum Key: String {
        case favoriteRoutes = "favoriteRoutes.v2"
        case recentRoutes = "recentRoutes.v2"
        case boards = "boards.v2"
        case recentPlaces = "recentPlaces.v2"
        case searchOptions = "searchOptions.v2"
        case lastLocation = "lastLocation.v2"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load<T: Decodable>(_ key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ key: Key) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
    }

    static var favoriteRoutes: [SavedRoute] { load(.favoriteRoutes) ?? [] }
    static var boards: [SavedBoard] { load(.boards) ?? [] }
    static var searchOptions: SearchOptions { load(.searchOptions) ?? SearchOptions() }

    /// Last location the app resolved – lets widgets use routes from "Moje poloha".
    static var lastLocation: Coordinate? {
        get { load(.lastLocation) }
        set { save(newValue, .lastLocation) }
    }
}
