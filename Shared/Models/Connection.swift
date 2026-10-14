import CoreLocation
import Foundation

/// One search result: a door-to-door journey made of rides, walks and waits.
struct Connection: Identifiable, Hashable, Sendable {
    let id: Int
    let departure: Date
    let arrival: Date
    let transferCount: Int
    var legs: [Leg]
    let prices: [Price]
    let startCoordinate: Coordinate?
    let endCoordinate: Coordinate?
    /// The searched places this result belongs to (relevant for multi-place searches).
    var origin: Place?
    var destination: Place?

    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    var rides: [RideLeg] { legs.compactMap { if case .ride(let r) = $0 { r } else { nil } } }
    var firstRide: RideLeg? { rides.first }

    /// Worst currently-reported delay among rides (seconds).
    var maxDelay: Int? { rides.compactMap(\.delay).max() }
    var hasWarnings: Bool { rides.contains { !$0.notices.isEmpty } }

    /// Estimated price of the whole journey (partial prices alone would be misleading).
    var totalPrice: Price? { prices.first { $0.kind == .total } }
    /// Tickets that can be bought online (whole journey or per carrier).
    var ticketOffers: [Price] { prices.filter { $0.url != nil } }

    /// When to leave: the first ride's departure including its current delay.
    var effectiveDeparture: Date {
        guard let ride = firstRide else { return departure }
        let delay = ride.boardStop.flatMap(ride.delay(at:)) ?? 0
        let walkBefore = legs.prefix { if case .ride = $0 { false } else { true } }
            .reduce(0) { $0 + $1.duration }
        return ride.departure.addingTimeInterval(TimeInterval(max(0, delay)) - walkBefore)
    }

    func replacingRides(_ transform: (RideLeg) -> RideLeg) -> Connection {
        var copy = self
        copy.legs = legs.map { if case .ride(let r) = $0 { .ride(transform(r)) } else { $0 } }
        return copy
    }

    /// Transfer between consecutive rides, accounting for live delays and walking time.
    func transfer(before rideID: RideLeg.ID) -> Transfer? {
        guard let index = rides.firstIndex(where: { $0.id == rideID }), index > 0 else { return nil }
        let previous = rides[index - 1]
        let next = rides[index]
        guard let legStart = legs.firstIndex(where: { $0.id == "r\(previous.id)" }),
            let legEnd = legs.firstIndex(where: { $0.id == "r\(next.id)" })
        else { return nil }
        let walking = legs[(legStart + 1)..<legEnd].reduce(0.0) { sum, leg in
            if case .walk(let w) = leg { sum + w.arrival.timeIntervalSince(w.departure) } else { sum }
        }
        let arrivalDelay = previous.alightStop.flatMap(previous.delay(at:)) ?? 0
        let departureDelay = max(0, next.boardStop.flatMap(next.delay(at:)) ?? 0)
        let planned = next.departure.timeIntervalSince(previous.arrival)
        let margin = planned + TimeInterval(departureDelay - max(0, arrivalDelay)) - walking
        return Transfer(planned: planned, walking: walking, margin: margin, delayKnown: previous.delay != nil)
    }
}

struct Transfer: Hashable, Sendable {
    let planned: TimeInterval
    let walking: TimeInterval
    /// Spare time after walking, adjusted for delays.
    let margin: TimeInterval
    let delayKnown: Bool

    enum Risk { case ok, tight, missed }
    var risk: Risk {
        if margin < 0 { return .missed }
        if margin < 120 { return .tight }
        return .ok
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

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
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
    case wait(WaitLeg)

    var id: String {
        switch self {
        case .ride(let r): "r\(r.id)"
        case .walk(let w): "w\(w.id)"
        case .wait(let w): "t\(w.id)"
        }
    }

    var departure: Date {
        switch self {
        case .ride(let r): r.departure
        case .walk(let w): w.departure
        case .wait(let w): w.departure
        }
    }

    var arrival: Date {
        switch self {
        case .ride(let r): r.arrival
        case .walk(let w): w.arrival
        case .wait(let w): w.arrival
        }
    }

    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
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
    var displayLine: String { LineName.short(line) }
    /// Train number or full designation when it differs from the public line ("Os 8102").
    var lineDetail: String? {
        let parts = line.components(separatedBy: " / ")
        // Zero-padded licence numbers ("000437") add nothing over the short line.
        return parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : nil
    }

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

enum LineName {
    /// `"Ex3 / rj 577"` → `"Ex3"`, licence numbers like `"000038"` → `"38"`.
    static func short(_ line: String) -> String {
        let first = line.components(separatedBy: " / ").first ?? line
        if first.count >= 6, first.allSatisfy(\.isNumber) {
            let trimmed = first.drop { $0 == "0" }
            return trimmed.isEmpty ? first : String(trimmed)
        }
        return first
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

/// Time spent waiting at a stop (between arriving/walking and the next departure).
struct WaitLeg: Identifiable, Hashable, Sendable {
    let id: Int
    let departure: Date
    let arrival: Date
}

struct Notice: Hashable, Sendable {
    let text: String
    let url: URL?
}

struct Price: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case total, partial }

    let kind: Kind
    let amount: Double
    let currency: String
    let seller: String?
    let from: String?
    let to: String?
    let url: URL?

    var formatted: String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

/// A row of a departure board.
struct Departure: Identifiable, Hashable, Sendable {
    let time: Date
    let line: String
    let vehicle: VehicleType
    let destination: String
    /// Set for boards combining several stops.
    var stopName: String?
    var id: String { "\(time.timeIntervalSince1970)|\(line)|\(destination)|\(stopName ?? "")" }
    var displayLine: String { LineName.short(line) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
