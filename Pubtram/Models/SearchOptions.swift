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

/// A saved/recent route pair.
struct SavedRoute: Codable, Hashable, Identifiable, Sendable {
    var from: Place
    var to: Place
    var id: String { from.id + "→" + to.id }
}
