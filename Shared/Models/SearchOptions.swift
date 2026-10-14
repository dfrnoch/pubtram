import Foundation

struct SearchOptions: Codable, Hashable, Sendable {
    var vehicles: Set<VehicleType> = Set(VehicleType.selectable)
    /// `nil` = no limit.
    var maxTransfers: Int?
    var lowFloor = false
    var stroller = false
    var bike = false
    var airCondition = false

    var isDefault: Bool { self == SearchOptions() }

    var rpcValue: RPCValue {
        var d: [String: RPCValue] = [
            "geometry": 0,
            "mobile": 1,
            "version": 3,
            "lowfloor": .int(lowFloor ? 1 : 0),
            "stroller": .int(stroller ? 1 : 0),
            "bike": .int(bike ? 1 : 0),
            "aircondition": .int(airCondition ? 1 : 0),
        ]
        for v in VehicleType.selectable {
            d[v.apiKey] = .int(vehicles.contains(v) ? 1 : 0)
        }
        if let maxTransfers { d["tcount"] = .int(maxTransfers) }
        return .dict(d)
    }

    var summary: String? {
        var parts: [String] = []
        if vehicles.count < VehicleType.selectable.count {
            parts.append(VehicleType.selectable.filter { vehicles.contains($0) }.map(\.name).joined(separator: ", "))
        }
        if let maxTransfers { parts.append(maxTransfers == 0 ? "bez přestupu" : "max. \(maxTransfers) přestupy") }
        if lowFloor { parts.append("bezbariérově") }
        if stroller { parts.append("s kočárkem") }
        if bike { parts.append("s kolem") }
        if airCondition { parts.append("klimatizace") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A saved/recent route. Each side may list several alternative places –
/// the search tries every combination and merges the results.
struct SavedRoute: Codable, Hashable, Identifiable, Sendable {
    var from: [Place]
    var to: [Place]
    var name: String?

    var id: String { from.map(\.id).joined(separator: "|") + "→" + to.map(\.id).joined(separator: "|") }
    var title: String { name ?? "\(from.label) → \(to.label)" }
    var placesLabel: String { "\(from.label) → \(to.label)" }
    var reversed: SavedRoute { SavedRoute(from: to, to: from) }
    var usesCurrentLocation: Bool { (from + to).contains(where: \.isCurrentLocation) }
}

/// A departure board combining one or more stops, optionally limited to some lines.
struct SavedBoard: Codable, Hashable, Identifiable, Sendable {
    var stops: [Place]
    var lines: [String] = []
    var name: String?

    var id: String { stops.map(\.id).joined(separator: "|") + "#" + lines.joined(separator: ",") }
    var title: String { name ?? stops.label }
    var subtitle: String? {
        var parts: [String] = []
        if name != nil { parts.append(stops.label) }
        if !lines.isEmpty { parts.append("linky " + lines.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Array where Element == Place {
    /// "Anděl", "Anděl nebo Na Knížecí", "Anděl a 2 další"
    var label: String {
        switch count {
        case 0: ""
        case 1: self[0].name
        case 2: "\(self[0].name) nebo \(self[1].name)"
        default: "\(self[0].name) a \(count - 1) další"
        }
    }
}
