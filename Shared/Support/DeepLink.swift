import Foundation

/// `pubtram://` URLs used by widgets, quick actions, Spotlight and Shortcuts.
enum DeepLink: Hashable, Sendable {
    case route(id: String)
    case board(id: String)
    case departures
    case search

    static let scheme = "pubtram"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
        switch url.host() {
        case "route": if let id { self = .route(id: id) } else { return nil }
        case "board": if let id { self = .board(id: id) } else { self = .departures }
        case "departures": self = .departures
        case "search": self = .search
        default: return nil
        }
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .route(let id):
            c.host = "route"
            c.queryItems = [URLQueryItem(name: "id", value: id)]
        case .board(let id):
            c.host = "board"
            c.queryItems = [URLQueryItem(name: "id", value: id)]
        case .departures:
            c.host = "departures"
        case .search:
            c.host = "search"
        }
        return c.url!
    }
}
