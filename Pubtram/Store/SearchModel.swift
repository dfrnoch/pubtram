import Foundation
import Observation

@MainActor @Observable
final class SearchModel {
    var from: Place?
    var to: Place?
    var via: Place?
    var showsVia = false
    /// `nil` means "now".
    var date: Date?
    var isDeparture = true

    private(set) var connections: [Connection] = []
    private(set) var searchedRoute: SavedRoute?
    private(set) var isSearching = false
    private(set) var isLoadingEarlier = false
    private(set) var isLoadingLater = false
    private(set) var error: String?
    private(set) var lastLiveRefresh: Date?
    var selectedID: Connection.ID?

    private var hashes: [Int] = []
    private var laterOffset = 0
    private var earlierOffset = 0
    private var searchDate = Date()
    private var resolvedFrom: Place?
    private var resolvedTo: Place?
    private var searchTask: Task<Void, Never>?

    private let client: PubtranClient
    let store: AppStore

    init(store: AppStore, client: PubtranClient = .shared) {
        self.store = store
        self.client = client
    }

    var canSearch: Bool { from != nil && to != nil }
    var hasResults: Bool { !connections.isEmpty }

    func connection(id: Connection.ID?) -> Connection? {
        connections.first { $0.id == id }
    }

    func swap() {
        (from, to) = (to, from)
    }

    func apply(_ route: SavedRoute) {
        from = route.from
        to = route.to
        search()
    }

    func clearResults() {
        searchTask?.cancel()
        connections = []
        searchedRoute = nil
        selectedID = nil
        error = nil
    }

    // MARK: Search

    func search() {
        guard let from, let to else { return }
        searchTask?.cancel()
        searchTask = Task { await performSearch(from: from, to: to) }
    }

    private func performSearch(from: Place, to: Place) async {
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let start = try await resolve(from)
            let end = try await resolve(to)
            resolvedFrom = start
            resolvedTo = end
            searchDate = date ?? .now
            let page = try await client.connections(
                from: start, to: end, via: showsVia ? via : nil, date: searchDate,
                isDeparture: isDeparture, options: store.searchOptions)
            try Task.checkCancellation()
            connections = page.connections
            hashes = page.hashes
            laterOffset = page.connections.count
            earlierOffset = 0
            lastLiveRefresh = .now
            selectedID = nil
            searchedRoute = SavedRoute(from: from, to: to)
            store.addRecent(SavedRoute(from: from, to: to))
            store.addRecent(place: from)
            store.addRecent(place: to)
            if connections.isEmpty { error = "Žádné spojení jsme nenašli." }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            connections = []
            self.error = error.localizedDescription
        }
    }

    func loadLater() async {
        guard let start = resolvedFrom, let end = resolvedTo, !isLoadingLater else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }
        do {
            let page = try await client.connections(
                from: start, to: end, via: showsVia ? via : nil, date: searchDate, isDeparture: isDeparture,
                options: store.searchOptions, index: laterOffset, usedHashes: hashes)
            laterOffset += max(page.connections.count, 1)
            merge(page)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadEarlier() async {
        guard let start = resolvedFrom, let end = resolvedTo, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            earlierOffset -= 5
            let page = try await client.connections(
                from: start, to: end, via: showsVia ? via : nil, date: searchDate, isDeparture: isDeparture,
                options: store.searchOptions, index: earlierOffset, usedHashes: hashes)
            merge(page)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func merge(_ page: PubtranClient.ConnectionPage) {
        let known = Set(connections.map(\.id))
        connections.append(contentsOf: page.connections.filter { !known.contains($0.id) })
        connections.sort { ($0.departure, $0.arrival) < ($1.departure, $1.arrival) }
        hashes.append(contentsOf: page.hashes.filter { !hashes.contains($0) })
    }

    private func resolve(_ place: Place) async throws -> Place {
        guard place.isCurrentLocation else { return place }
        return .currentLocation(try await LocationProvider.current())
    }

    // MARK: Live updates

    /// Refreshes delays/platforms for the given connections (all loaded ones by default).
    func refreshLive(only ids: Set<Connection.ID>? = nil) async {
        let targets = connections.filter { ids?.contains($0.id) ?? true }
        let rides = targets.flatMap(\.rides).filter { $0.arrival > .now.addingTimeInterval(-600) }
        guard !rides.isEmpty, let info = try? await client.liveInfo(for: rides) else { return }
        connections = connections.map { c in
            c.replacingRides { ride in info[ride.id].map(ride.applying) ?? ride }
        }
        lastLiveRefresh = .now
    }
}

extension RideLeg {
    func applying(_ live: LiveInfo) -> RideLeg {
        var copy = self
        copy.delay = live.delay ?? delay
        copy.delayText = live.delayText ?? delayText
        copy.platform = live.platform ?? platform
        copy.notices = live.notices.isEmpty ? notices : live.notices
        copy.stopDelays.merge(live.stopDelays) { $1 }
        copy.stopPlatforms.merge(live.stopPlatforms) { $1 }
        copy.features.formUnion(live.features)
        copy.vehiclePosition = live.vehiclePosition ?? vehiclePosition
        return copy
    }
}
