import CoreLocation

/// A searchable location: stop, address, POI, town or raw coordinates.
struct Place: Codable, Hashable, Sendable, Identifiable {
    /// Identifier in Seznam's place database (0 for raw coordinates).
    var placeID: Int
    /// `pubt` (public transport stop), `addr`, `muni`, `firm`, `poi`, `area`, `coor`, …
    var source: String
    var name: String
    var subtitle: String?
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool = false

    var id: String { isCurrentLocation ? "current" : "\(source):\(placeID):\(latitude),\(longitude)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isStop: Bool { source == "pubt" }

    static func currentLocation(_ coordinate: CLLocationCoordinate2D) -> Place {
        Place(
            placeID: 0, source: "coor", name: "Moje poloha", subtitle: nil,
            latitude: coordinate.latitude, longitude: coordinate.longitude, isCurrentLocation: true)
    }

    var rpcValue: RPCValue {
        ["id": .int(placeID), "source": .string(source), "x": .double(longitude), "y": .double(latitude)]
    }

    var symbol: String {
        if isCurrentLocation { return "location.fill" }
        switch source {
        case "pubt": return "signpost.right.fill"
        case "addr": return "house.fill"
        case "muni", "area": return "building.2.fill"
        case "firm": return "storefront.fill"
        case "coor": return "mappin"
        default: return "mappin.circle.fill"
        }
    }
}
