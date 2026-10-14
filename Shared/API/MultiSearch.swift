import Foundation

/// Searches every origin × destination combination and merges the results,
/// so "Anděl or Na Knížecí → Letňany" works like a single search.
struct MultiSearch: Sendable {
    struct Pair: Sendable {
        let from: Place
        let to: Place
        var laterOffset = 0
        var earlierOffset = 0
        var hashes: [Int] = []
    }

    enum Direction { case initial, later, earlier }

    static let maxPlacesPerSide = 4

    let client: PubtranClient
    let via: Place?
    let date: Date
    let isDeparture: Bool
    let options: SearchOptions
    private(set) var pairs: [Pair]

    init(
        from: [Place], to: [Place], via: Place?, date: Date, isDeparture: Bool, options: SearchOptions,
        client: PubtranClient = .shared
    ) {
        self.client = client
        self.via = via
        self.date = date
        self.isDeparture = isDeparture
        self.options = options
        pairs = from.prefix(Self.maxPlacesPerSide).flatMap { f in
            to.prefix(Self.maxPlacesPerSide).compactMap { t in f.id == t.id ? nil : Pair(from: f, to: t) }
        }
    }

    /// Fetches a page for every pair in parallel. Pairs that fail are skipped
    /// unless all of them fail, in which case the first error is thrown.
    mutating func fetch(_ direction: Direction, count: Int = 5) async throws -> [Connection] {
        let snapshot = pairs
        let results = await withTaskGroup(of: (Int, Result<PubtranClient.ConnectionPage, Error>).self) { group in
            for (index, pair) in snapshot.enumerated() {
                let offset: Int
                switch direction {
                case .initial: offset = 0
                case .later: offset = pair.laterOffset
                case .earlier: offset = pair.earlierOffset - count
                }
                group.addTask { [client, via, date, isDeparture, options] in
                    do {
                        let page = try await client.connections(
                            from: pair.from, to: pair.to, via: via, date: date, isDeparture: isDeparture,
                            options: options, index: offset, count: count,
                            usedHashes: direction == .initial ? [] : pair.hashes)
                        return (index, .success(page))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<PubtranClient.ConnectionPage, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var connections: [Connection] = []
        var firstError: Error?
        for (index, result) in results {
            switch result {
            case .success(let page):
                switch direction {
                case .initial:
                    pairs[index].laterOffset = page.connections.count
                    pairs[index].earlierOffset = 0
                    pairs[index].hashes = page.hashes
                case .later:
                    pairs[index].laterOffset += max(page.connections.count, 1)
                    pairs[index].hashes += page.hashes
                case .earlier:
                    pairs[index].earlierOffset -= count
                    pairs[index].hashes += page.hashes
                }
                let pair = pairs[index]
                connections += page.connections.map { c in
                    var c = c
                    c.origin = pair.from
                    c.destination = pair.to
                    return c
                }
            case .failure(let error):
                if let api = error as? APIError, api.isNotFound { continue }
                firstError = firstError ?? error
            }
        }
        if connections.isEmpty, let firstError, results.allSatisfy({ if case .failure = $0.1 { true } else { false } }) {
            throw firstError
        }
        return connections
    }
}

extension PubtranClient {
    /// Next few connections for a saved route – used by widgets and Shortcuts.
    func upcomingConnections(for route: SavedRoute, count: Int = 3, options: SearchOptions? = nil) async throws
        -> [Connection]
    {
        let resolve: (Place) -> Place? = { place in
            guard place.isCurrentLocation else { return place }
            return SharedStore.lastLocation.map { .currentLocation($0.cl) }
        }
        let from = route.from.compactMap(resolve)
        let to = route.to.compactMap(resolve)
        var search = MultiSearch(
            from: from, to: to, via: nil, date: .now, isDeparture: true,
            options: options ?? SharedStore.searchOptions, client: self)
        let results = try await search.fetch(.initial, count: count)
        return Array(Self.merge(results).filter { $0.effectiveDeparture > .now.addingTimeInterval(-60) }.prefix(count))
    }

    /// De-duplicates and sorts connections by departure, then arrival.
    static func merge(_ connections: [Connection]) -> [Connection] {
        var seen = Set<Int>()
        return connections.filter { seen.insert($0.id).inserted }
            .sorted { ($0.departure, $0.arrival) < ($1.departure, $1.arrival) }
    }

    /// Departures for a board combining several stops, filtered to its lines.
    func departures(for board: SavedBoard, after date: Date = .now.addingTimeInterval(-60), count: Int = 40)
        async throws -> [Departure]
    {
        let multiple = board.stops.count > 1
        let results = await withTaskGroup(of: Result<[Departure], Error>.self) { group in
            for stop in board.stops {
                group.addTask { [self] in
                    do {
                        let list = try await departures(from: stop, after: date, count: count)
                        return .success(multiple ? list.map { d in var d = d; d.stopName = stop.name; return d } : list)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<[Departure], Error>] = []
            for await r in group { collected.append(r) }
            return collected
        }
        var all: [Departure] = []
        for result in results {
            switch result {
            case .success(let list): all += list
            case .failure(let error): if results.allSatisfy({ if case .failure = $0 { true } else { false } }) { throw error }
            }
        }
        let lines = Set(board.lines)
        var seen = Set<String>()
        return all
            .filter { lines.isEmpty || lines.contains($0.line) || lines.contains($0.displayLine) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.time < $1.time }
    }
}
