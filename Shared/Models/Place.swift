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

extension Place {
    /// Suggest subtitle split into parts, without the trailing country.
    private var subtitleParts: [String] {
        var parts = (subtitle ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let last = parts.last, ["Česko", "Czechia", "Česká republika"].contains(last) { parts.removeLast() }
        return parts
    }

    /// Modes serving a stop, parsed from e.g. "Zastávka tramvaje, autobusu, Brno, Česko".
    var stopModes: [VehicleType] {
        guard isStop else { return [] }
        let keys: [(String, VehicleType)] = [
            ("metr", .metro), ("tramvaj", .tram), ("trolejbus", .trolley), ("autobus", .bus),
            ("vlak", .train), ("železni", .train), ("lanov", .cable), ("přívoz", .ferry), ("lod", .ferry),
        ]
        var modes: [VehicleType] = []
        for part in subtitleParts.dropLast() {
            let lower = part.lowercased()
            for (key, mode) in keys where lower.contains(key) && !modes.contains(mode) {
                modes.append(mode)
            }
        }
        return modes
    }

    /// Short location line: the town for stops ("Brno"), the subtitle without country otherwise.
    /// When the stop name already starts with the town, the stop kind is shown instead ("Vlaková stanice").
    var shortSubtitle: String? {
        let parts = subtitleParts
        guard let last = parts.last else { return nil }
        guard isStop else { return parts.joined(separator: ", ") }
        if name.hasPrefix(last), parts.count > 1 { return parts[0] }
        return last
    }
}
