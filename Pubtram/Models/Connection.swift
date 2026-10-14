import CoreLocation
import Foundation

/// One search result: a door-to-door journey made of rides and walks.
struct Connection: Identifiable, Hashable, Sendable {
    let id: Int
    let departure: Date
    let arrival: Date
    let transferCount: Int
    let legs: [Leg]
    let prices: [Price]
    let startCoordinate: Coordinate?
    let endCoordinate: Coordinate?

    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    var rides: [RideLeg] { legs.compactMap { if case .ride(let r) = $0 { r } else { nil } } }
    var firstRide: RideLeg? { rides.first }

    /// Worst currently-reported delay among rides (seconds).
    var maxDelay: Int? { rides.compactMap(\.delay).max() }
    var hasWarnings: Bool { rides.contains { !$0.notices.isEmpty } }

    func replacingRides(_ transform: (RideLeg) -> RideLeg) -> Connection {
        Connection(
            id: id, departure: departure, arrival: arrival, transferCount: transferCount,
            legs: legs.map { if case .ride(let r) = $0 { .ride(transform(r)) } else { $0 } },
            prices: prices, startCoordinate: startCoordinate, endCoordinate: endCoordinate)
    }
}

struct Coordinate: Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// API sends `[lon, lat]` pairs.
    init?(pair: RPCValue?) {
        let a = pair?.array ?? []
        guard a.count >= 2, let lon = a[0].double, let lat = a[1].double else { return nil }
        self.init(latitude: lat, longitude: lon)
    }
}

enum Leg: Identifiable, Hashable, Sendable {
    case ride(RideLeg)
    case walk(WalkLeg)

    var id: String {
        switch self {
        case .ride(let r): "r\(r.id)"
        case .walk(let w): "w\(w.id)"
        }
    }

    var departure: Date {
        switch self {
        case .ride(let r): r.departure
        case .walk(let w): w.departure
        }
    }

    var arrival: Date {
        switch self {
        case .ride(let r): r.arrival
        case .walk(let w): w.arrival
        }
    }
}

struct RideLeg: Identifiable, Hashable, Sendable {
    let id: String  // partDescription – also the key for live info & trip detail
    let tripID: Int
    let vehicle: VehicleType
    let line: String
    let agency: String?
    let departure: Date
    let arrival: Date
    /// Every stop of the vehicle's trip; `boardIndex`/`alightIndex` mark the ridden part.
    let stops: [StopTime]
    let boardIndex: Int
    let alightIndex: Int
    var platform: String?
    var features: Set<Feature>
    var delay: Int?
    var delayText: String?
    var notices: [Notice]
    /// Predicted delay per stop ID (seconds).
    var stopDelays: [Int: Int]
    /// Platform / track per stop ID.
    var stopPlatforms: [Int: String]
    var vehiclePosition: Coordinate?

    var boardStop: StopTime? { stops[safe: boardIndex] }
    var alightStop: StopTime? { stops[safe: alightIndex] }
    var direction: String { stops.last?.name ?? "" }
    var riddenStops: ArraySlice<StopTime> {
        guard boardIndex <= alightIndex, alightIndex < stops.count else { return [] }
        return stops[boardIndex...alightIndex]
    }
    var intermediateStopCount: Int { max(0, alightIndex - boardIndex - 1) }

    var boardPlatform: String? {
        boardStop.flatMap(livePlatform(at:)) ?? platform ?? boardStop?.platform
    }

    var alightPlatform: String? {
        alightStop.flatMap { livePlatform(at: $0) ?? $0.platform }
    }

    /// Live info may be keyed by either the stop or its parent station.
    func livePlatform(at stop: StopTime) -> String? {
        stopPlatforms[stop.stopID] ?? stop.parentID.flatMap { stopPlatforms[$0] }
    }

    /// Delay applicable at a given stop (prediction if available, else the trip-wide delay).
    func delay(at stop: StopTime) -> Int? {
        stopDelays[stop.stopID] ?? stop.parentID.flatMap { stopDelays[$0] } ?? delay
    }

    enum Feature: String, Hashable, Sendable {
        case lowFloor, wifi, airCondition, bike
        var symbol: String {
            switch self {
            case .lowFloor: "figure.roll"
            case .wifi: "wifi"
            case .airCondition: "snowflake"
            case .bike: "bicycle"
            }
        }
        var label: String {
            switch self {
            case .lowFloor: "Bezbariérové vozidlo"
            case .wifi: "Wi-Fi"
            case .airCondition: "Klimatizace"
            case .bike: "Přeprava kol"
            }
        }
    }
}

struct StopTime: Identifiable, Hashable, Sendable {
    let id: Int  // position in the trip
    let stopID: Int
    let parentID: Int?
    let name: String
    let coordinate: Coordinate?
    let arrival: Date?
    let departure: Date?
    let platform: String?
    let zone: String?
    let onRequest: Bool

    var time: Date? { departure ?? arrival }
}

struct WalkLeg: Identifiable, Hashable, Sendable {
    let id: Int
    let departure: Date
    let arrival: Date
    let distance: Int
    let from: Coordinate?
    let to: Coordinate?
}

struct Notice: Hashable, Sendable {
    let text: String
    let url: URL?
}

struct Price: Hashable, Sendable {
    let amount: Double
    let currency: String
    let seller: String?
    let url: URL?

    var formatted: String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

/// A row of the stop departure board.
struct Departure: Identifiable, Hashable, Sendable {
    let time: Date
    let line: String
    let vehicle: VehicleType
    let destination: String
    var id: String { "\(time.timeIntervalSince1970)|\(line)|\(destination)" }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
