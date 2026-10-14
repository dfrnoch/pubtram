import CoreLocation
import Foundation

enum APIError: LocalizedError {
    case http(Int)
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let code): "Server odpověděl chybou \(code)."
        case .status(404, _): "Žádné spojení jsme nenašli."
        case .status(_, let message): message.isEmpty ? "Vyhledávání selhalo." : message
        }
    }

    var isNotFound: Bool {
        if case .status(404, _) = self { return true }
        return false
    }
}

/// Client for the public-transport backend behind seznam.cz/jizdnirady.
struct PubtranClient: Sendable {
    static let shared = PubtranClient()

    private let base = URL(string: "https://jizdnirady.seznam.cz")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Places

    enum SuggestKind: Sendable {
        case any, stops
        var types: String {
            switch self {
            case .any: "municipality|address|poi|area|firm|pubt"
            case .stops: "pubt"
            }
        }
    }

    func suggest(_ phrase: String, near: CLLocationCoordinate2D?, kind: SuggestKind = .any) async throws -> [Place] {
        var components = URLComponents(url: base.appending(path: "suggest"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "phrase", value: phrase),
            .init(name: "limit", value: "10"),
            .init(name: "zoom", value: "16"),
            .init(name: "pubtBoost", value: "1"),
            .init(name: "type", value: kind.types),
            .init(name: "subtype", value: "small_area"),
        ]
        if let near {
            items.append(.init(name: "lat", value: String(near.latitude)))
            items.append(.init(name: "lon", value: String(near.longitude)))
        }
        components.queryItems = items
        let (data, response) = try await session.data(from: components.url!)
        try Self.check(response)
        let decoded = try JSONDecoder().decode(SuggestResponse.self, from: data)
        let places = decoded.result.compactMap { $0.userData.place }
        return kind == .stops ? places.filter(\.isStop) : places
    }

    // MARK: Connections

    struct ConnectionPage: Sendable {
        let connections: [Connection]
        let hashes: [Int]
    }

    /// - Parameters:
    ///   - index: offset relative to `date`; negative values return earlier connections.
    ///   - usedHashes: hashes of already loaded connections, so the server skips them.
    func connections(
        from: Place, to: Place, via: Place?, date: Date, isDeparture: Bool, options: SearchOptions,
        index: Int = 0, count: Int = 5, usedHashes: [Int] = []
    ) async throws -> ConnectionPage {
        var opts = options.rpcValue
        if case .dict(var d) = opts, !usedHashes.isEmpty {
            d["hashes_used"] = .array(usedHashes.map(RPCValue.int))
            opts = .dict(d)
        }
        let query: RPCValue = [
            "start": from.rpcValue,
            "end": to.rpcValue,
            "mid": .array(via.map { [$0.rpcValue] } ?? []),
            "index": .int(index),
            "count": .int(count),
        ]
        let value = try await call("getRoutesOpt", [.date(date), .bool(isDeparture), query, opts])
        return ConnectionPage(
            connections: ResponseParser.connections(value),
            hashes: value["hashes"]?.array.compactMap(\.int) ?? [])
    }

    // MARK: Live info

    /// Fresh delays / platforms / notices for the given rides, keyed by ride ID.
    func liveInfo(for rides: [RideLeg]) async throws -> [String: LiveInfo] {
        guard !rides.isEmpty else { return [:] }
        let query = RPCValue.array(
            rides.map { ["tripId": .string($0.id), "time": .date($0.departure)] })
        let value = try await call("getTripInfo", [query])
        var result: [String: LiveInfo] = [:]
        for (ride, info) in zip(rides, value.array) where (info["status"]?.int ?? 0) == 200 {
            result[ride.id] = ResponseParser.liveInfo(info["info"]?.array ?? [])
        }
        return result
    }

    // MARK: Geometry

    func rideGeometry(_ ride: RideLeg) async throws -> [CLLocationCoordinate2D] {
        let value = try await call(
            "getTripDetail",
            [
                .string(ride.id),
                ["startindex": 0, "endindex": .int(max(0, ride.stops.count - 1)), "time": .date(ride.departure)],
            ])
        return GeometryDecoder.decode(value["trip"]?["geom"]?.string ?? "")
    }

    func walkGeometry(from: Coordinate, to: Coordinate) async throws -> [CLLocationCoordinate2D] {
        let value = try await call(
            "getWalkGeom",
            [
                [
                    "start": ["x": .double(from.longitude), "y": .double(from.latitude)],
                    "end": ["x": .double(to.longitude), "y": .double(to.latitude)],
                ]
            ])
        return GeometryDecoder.decode(value["geom"]?["geom"]?.string ?? "")
    }

    // MARK: Departure board

    func departures(from stop: Place, after date: Date, count: Int = 40) async throws -> [Departure] {
        let query: RPCValue = [
            "start": stop.rpcValue, "end": stop.rpcValue, "mid": [], "index": 0, "count": .int(count),
        ]
        do {
            let value = try await call("getStopDepartures", [.date(date), query, ["version": 3]])
            return value["departures"]?.array.compactMap { d in
                guard let time = d["departureISO"]?.isoDate else { return nil }
                return Departure(
                    time: time,
                    line: d["routeName"]?.string ?? "",
                    vehicle: VehicleType(apiValue: d["vehicleType"]?.int),
                    destination: d["finalStop"]?.string ?? "")
            } ?? []
        } catch let error as APIError where error.isNotFound {
            return []
        }
    }

    // MARK: Transport

    private func call(_ method: String, _ params: [RPCValue]) async throws -> RPCValue {
        var request = URLRequest(url: base.appending(path: "routept/"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/xml", forHTTPHeaderField: "Accept")
        request.httpBody = XMLRPCEncoder.methodCall(method, params: params)
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        let value = try XMLRPCDecoder.decode(data)
        if let status = value["status"]?.int, !(200...299).contains(status) {
            throw APIError.status(status, value["statusMessage"]?.string ?? "")
        }
        return value
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
    }
}

// MARK: - Suggest JSON

private struct SuggestResponse: Decodable {
    let result: [Item]

    struct Item: Decodable {
        let userData: UserData
    }

    struct UserData: Decodable {
        let id: Int?
        let source: String?
        let suggestFirstRow: String?
        let suggestSecondRow: String?
        let latitude: Double?
        let longitude: Double?

        var place: Place? {
            guard let source, let latitude, let longitude, let name = suggestFirstRow else { return nil }
            return Place(
                placeID: id ?? 0, source: source, name: name, subtitle: suggestSecondRow,
                latitude: latitude, longitude: longitude)
        }
    }
}
