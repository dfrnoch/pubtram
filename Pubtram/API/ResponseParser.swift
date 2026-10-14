import Foundation

/// Real-time information attached to a trip (delays, platforms, disruptions, vehicle position).
struct LiveInfo: Sendable {
    var delay: Int?
    var delayText: String?
    var platform: String?
    var notices: [Notice] = []
    var stopDelays: [Int: Int] = [:]
    var stopPlatforms: [Int: String] = [:]
    var features: Set<RideLeg.Feature> = []
    var vehiclePosition: Coordinate?
}

/// Info / stop-time code IDs used by the backend.
enum InfoCode {
    static let zone = 7
    static let lowFloorVehicle = 15
    static let bike = 20
    static let stopOnRequest = 28
    static let platformName = 42
    static let wifi = 45
    static let airCondition = 46
    static let platformTrack = 400
    static let entranceName = 443
    static let delayPrediction = 500
    static let warnings: Set<Int> = [14, 101, 102, 103, 104, 105, 106, 107, 108, 201, 202, 203, 204, 205]
    static let hiddenDelay: Set<Int> = [303, 304, 305]
    static let platformCodes: Set<Int> = [platformName, platformTrack, entranceName]
}

enum ResponseParser {
    static func connections(_ value: RPCValue) -> [Connection] {
        let stops = value["stops"]?.array ?? []
        let agencies = value["agenciesinfo"]?.array ?? []

        return value["routes"]?.array.compactMap { route -> Connection? in
            guard let departure = route["departureISO"]?.isoDate,
                let arrival = route["arrivalISO"]?.isoDate
            else { return nil }

            var legs: [Leg] = []
            for (n, item) in (route["items"]?.array ?? []).enumerated() {
                switch item["type"]?.int {
                case 0:
                    if let ride = ride(item, stops: stops, agencies: agencies) { legs.append(.ride(ride)) }
                case 1:
                    if let walk = walk(item, index: n) { legs.append(.walk(walk)) }
                default:
                    break
                }
            }

            let prices = route["payment"]?.array.compactMap { p -> Price? in
                guard p["type"]?.string == "price", let amount = p["price"]?.double else { return nil }
                return Price(
                    amount: amount,
                    currency: p["currency_type"]?.string ?? "CZK",
                    seller: p["eshopName"]?.string ?? p["source"]?["name"]?.string,
                    url: (p["url"]?.string).flatMap(URL.init(string:)))
            } ?? []

            return Connection(
                id: route["hash"]?.int ?? Int(departure.timeIntervalSince1970),
                departure: departure,
                arrival: arrival,
                transferCount: route["transferCount"]?.int ?? max(0, legs.filter { if case .ride = $0 { true } else { false } }.count - 1),
                legs: legs,
                prices: prices,
                startCoordinate: Coordinate(pair: route["startPos"]),
                endCoordinate: Coordinate(pair: route["endPos"]))
        } ?? []
    }

    private static func ride(_ item: RPCValue, stops: [RPCValue], agencies: [RPCValue]) -> RideLeg? {
        guard let id = item["partDescription"]?.string,
            let departure = item["departureISO"]?.isoDate,
            let arrival = item["arrivalISO"]?.isoDate
        else { return nil }

        let tripStops: [StopTime] = item["tripData"]?.array.enumerated().map { n, t in
            let stop = stops[safe: t["stopIndex"]?.int ?? -1]
            let codes = t["stCodes"]?.array ?? []
            let platformText = codes.first { InfoCode.platformCodes.contains($0["id"]?.int ?? -1) }?["text"]?.string
            let zoneText = codes.first { $0["id"]?.int == InfoCode.zone }?["text"]?.string
            return StopTime(
                id: n,
                stopID: stop?["id"]?.int ?? 0,
                parentID: stop?["parent_id"]?.int,
                name: stop?["name"]?.string ?? "?",
                coordinate: Coordinate(pair: stop?["coord"]),
                arrival: t["arrivalISO"]?.isoDate,
                departure: t["departureISO"]?.isoDate,
                platform: platformText.flatMap(Platform.normalize),
                zone: zoneText.flatMap { $0.isEmpty ? nil : $0 },
                onRequest: codes.contains { $0["id"]?.int == InfoCode.stopOnRequest })
        } ?? []

        let agency = agencies[safe: item["agencyIndex"]?.int ?? -1].flatMap { a -> String? in
            let short = a["short_name"]?.string ?? ""
            return short.isEmpty ? a["name"]?.string : short
        }
        let live = liveInfo(item["info"]?.array ?? [])

        return RideLeg(
            id: id,
            tripID: item["tripID"]?.int ?? 0,
            vehicle: VehicleType(apiValue: item["vehicleType"]?.int),
            line: item["routeName"]?.string ?? "",
            agency: agency,
            departure: departure,
            arrival: arrival,
            stops: tripStops,
            boardIndex: item["startStopTripIndex"]?.int ?? 0,
            alightIndex: item["endStopTripIndex"]?.int ?? max(0, tripStops.count - 1),
            platform: live.platform,
            features: live.features,
            delay: live.delay,
            delayText: live.delayText,
            notices: live.notices,
            stopDelays: live.stopDelays,
            stopPlatforms: live.stopPlatforms,
            vehiclePosition: live.vehiclePosition)
    }

    private static func walk(_ item: RPCValue, index: Int) -> WalkLeg? {
        guard let departure = item["departureISO"]?.isoDate, let arrival = item["arrivalISO"]?.isoDate else {
            return nil
        }
        return WalkLeg(
            id: index,
            departure: departure,
            arrival: arrival,
            distance: item["distance"]?.int ?? 0,
            from: Coordinate(pair: item["oznStartCoord"]),
            to: Coordinate(pair: item["oznEndCoord"]))
    }

    static func liveInfo(_ items: [RPCValue]) -> LiveInfo {
        var info = LiveInfo()
        for entry in items {
            guard let code = entry["id"]?.int else { continue }
            let text = entry["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stopID = entry["stopID"]?.int

            if let lat = entry["lat"]?.double, let lon = entry["lon"]?.double {
                info.vehiclePosition = Coordinate(latitude: lat, longitude: lon)
            }

            switch code {
            case InfoCode.lowFloorVehicle: info.features.insert(.lowFloor)
            case InfoCode.wifi: info.features.insert(.wifi)
            case InfoCode.airCondition: info.features.insert(.airCondition)
            case InfoCode.bike: info.features.insert(.bike)
            case InfoCode.platformName, InfoCode.entranceName:
                if info.platform == nil { info.platform = Platform.normalize(text) }
            case InfoCode.platformTrack:
                if let stopID, let p = Platform.normalize(text) { info.stopPlatforms[stopID] = p }
            case InfoCode.delayPrediction:
                if let stopID, let d = entry["delay"]?.int { info.stopDelays[stopID] = d }
            case 300..<400 where !InfoCode.hiddenDelay.contains(code):
                if let d = entry["delay"]?.int {
                    info.delay = d
                    info.delayText = text.isEmpty ? nil : text
                }
            case _ where InfoCode.warnings.contains(code):
                if !text.isEmpty {
                    info.notices.append(Notice(text: text, url: (entry["url"]?.string).flatMap(URL.init(string:))))
                }
            default:
                break
            }
        }
        return info
    }
}

enum Platform {
    /// Collapses padding the backend sends (e.g. `" 5   / -"` → `"5 / -"`), dropping empty values.
    static func normalize(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty || collapsed == "-" || collapsed == "- / -" ? nil : collapsed
    }

    /// Human-readable form: `"4 / 14"` → `"nást. 4 · kol. 14"`, `"- / 8"` → `"kol. 8"`, `"D"` → `"stan. D"`.
    static func label(_ normalized: String) -> String {
        let parts = normalized.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return "stan. \(normalized)" }
        let platform = parts[0] == "-" || parts[0].isEmpty ? nil : "nást. \(parts[0])"
        let track = parts[1] == "-" || parts[1].isEmpty ? nil : "kol. \(parts[1])"
        return [platform, track].compactMap { $0 }.joined(separator: " · ")
    }
}
