import Foundation
import Observation

enum PlaceField: String, Identifiable, Hashable {
    case from, to, via
    var id: String { rawValue }

    var title: String {
        switch self {
        case .from: "Odkud"
        case .to: "Kam"
        case .via: "Přes"
        }
    }
}

@MainActor @Observable
final class SearchModel {
    enum Sort: String, CaseIterable, Identifiable {
        case departure, arrival, duration, transfers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .departure: "Podle odjezdu"
            case .arrival: "Podle příjezdu"
            case .duration: "Podle doby cesty"
            case .transfers: "Podle přestupů"
            }
        }
        /// Label for the sort chip.
        var shortTitle: String {
            switch self {
            case .departure: "Odjezd"
            case .arrival: "Příjezd"
            case .duration: "Nejrychlejší"
            case .transfers: "Nejméně přestupů"
            }
        }
    }

    // Form
    var from: [Place] = []
    var to: [Place] = []
    var via: Place?
    var showsVia = false
    /// `nil` means "now".
    var date: Date?
    var isDeparture = true

    // Navigation
    var showsResults = false
    var selectedID: Connection.ID?

    // Results presentation
    var sort: Sort = .departure
    var lineFilter: Set<String> = []

    private(set) var connections: [Connection] = []
    private(set) var searchedRoute: SavedRoute?
    private(set) var searchedDate = Date()
    private(set) var isSearching = false
    private(set) var isLoadingEarlier = false
    private(set) var isLoadingLater = false
    private(set) var canLoadLater = true
    private(set) var error: String?

    private var multiSearch: MultiSearch?
    private var searchTask: Task<Void, Never>?
    let store: AppStore

    init(store: AppStore) {
        self.store = store
    }

    var canSearch: Bool { !from.isEmpty && !to.isEmpty }
    var hasResults: Bool { !connections.isEmpty }

    func connection(id: Connection.ID?) -> Connection? {
        connections.first { $0.id == id }
    }

    // MARK: Form editing

    func places(for field: PlaceField) -> [Place] {
        switch field {
        case .from: from
        case .to: to
        case .via: via.map { [$0] } ?? []
        }
    }

    /// Replaces the place at `index`, or appends when `index` is nil.
    func set(_ place: Place, for field: PlaceField, at index: Int?) {
        switch field {
        case .from: from = Self.updating(from, with: place, at: index)
        case .to: to = Self.updating(to, with: place, at: index)
        case .via: via = place
        }
    }

    func remove(at index: Int, from field: PlaceField) {
        switch field {
        case .from: if from.indices.contains(index) { from.remove(at: index) }
        case .to: if to.indices.contains(index) { to.remove(at: index) }
        case .via:
            via = nil
            showsVia = false
        }
    }

    private static func updating(_ list: [Place], with place: Place, at index: Int?) -> [Place] {
        var list = list.filter { $0.id != place.id }
        if let index, index < list.count + 1 {
            if index < list.count { list[index] = place } else { list.append(place) }
        } else {
            list.append(place)
        }
        return Array(list.prefix(MultiSearch.maxPlacesPerSide))
    }

    func swap() {
        (from, to) = (to, from)
    }

    func apply(_ route: SavedRoute) {
        from = route.from
        to = route.to
        via = nil
        showsVia = false
        date = nil
        isDeparture = true
        search()
    }

    func goHome() {
        searchTask?.cancel()
        showsResults = false
        selectedID = nil
    }

    // MARK: Results

    var visibleConnections: [Connection] {
        let filtered = lineFilter.isEmpty
            ? connections
            : connections.filter { c in c.rides.contains { lineFilter.contains($0.displayLine) } }
        switch sort {
        case .departure: return filtered
        case .arrival: return filtered.sorted { ($0.arrival, $0.departure) < ($1.arrival, $1.departure) }
        case .duration: return filtered.sorted { ($0.duration, $0.departure) < ($1.duration, $1.departure) }
        case .transfers:
            return filtered.sorted {
                ($0.transferCount, $0.arrival.timeIntervalSince1970)
                    < ($1.transferCount, $1.arrival.timeIntervalSince1970)
            }
        }
    }

    /// Lines appearing in the results – offered as quick filters.
    var availableLines: [(line: String, vehicle: VehicleType)] {
        var seen: [String: VehicleType] = [:]
        var order: [String] = []
        for ride in connections.flatMap(\.rides) where ride.vehicle != .walk {
            if seen[ride.displayLine] == nil {
                seen[ride.displayLine] = ride.vehicle
                order.append(ride.displayLine)
            }
        }
        return order.map { ($0, seen[$0]!) }
    }

    var fastestID: Connection.ID? {
        guard connections.count > 1 else { return nil }
        return connections.min { $0.duration < $1.duration }?.id
    }

    // MARK: Search

    func search() {
        guard canSearch else { return }
        let from = self.from
        let to = self.to
        searchTask?.cancel()
        showsResults = true
        selectedID = nil
        lineFilter = []
        searchTask = Task { await performSearch(from: from, to: to) }
    }

    private func performSearch(from: [Place], to: [Place]) async {
        isSearching = true
        error = nil
        connections = []
        defer { isSearching = false }
        do {
            let start = try await resolve(from)
            let end = try await resolve(to)
            searchedDate = date ?? .now
            var search = MultiSearch(
                from: start, to: end, via: showsVia ? via : nil, date: searchedDate,
                isDeparture: isDeparture, options: store.searchOptions)
            let results = try await search.fetch(.initial)
            try Task.checkCancellation()
            multiSearch = search
            connections = PubtranClient.merge(results)
            canLoadLater = true
            let route = SavedRoute(from: from, to: to)
            searchedRoute = route
            store.addRecent(route)
            (from + to).forEach(store.addRecent(place:))
            if connections.isEmpty { error = "Žádné spojení jsme nenašli." }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadLater() async {
        guard var search = multiSearch, !isLoadingLater, !isSearching, canLoadLater else { return }
        isLoadingLater = true
        defer { isLoadingLater = false }
        do {
            let page = try await search.fetch(.later)
            multiSearch = search
            let before = connections.count
            connections = PubtranClient.merge(connections + page)
            canLoadLater = connections.count > before
        } catch {
            canLoadLater = false
        }
    }

    func loadEarlier() async {
        guard var search = multiSearch, !isLoadingEarlier, !isSearching else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        if let page = try? await search.fetch(.earlier) {
            multiSearch = search
            connections = PubtranClient.merge(connections + page)
        }
    }

    private func resolve(_ places: [Place]) async throws -> [Place] {
        var resolved: [Place] = []
        for place in places {
            if place.isCurrentLocation {
                resolved.append(.currentLocation(try await LocationProvider.current()))
            } else {
                resolved.append(place)
            }
        }
        return resolved
    }

    // MARK: Live updates

    /// Refreshes delays/platforms for the given connections (all loaded ones by default).
    func refreshLive(only ids: Set<Connection.ID>? = nil) async {
        let targets = connections.filter { ids?.contains($0.id) ?? true }
        let rides = targets.flatMap(\.rides).filter { $0.arrival > .now.addingTimeInterval(-600) }
        guard !rides.isEmpty, let info = try? await PubtranClient.shared.liveInfo(for: rides) else { return }
        connections = connections.map { c in
            c.replacingRides { ride in info[ride.id].map(ride.applying) ?? ride }
        }
        for id in ids ?? [] {
            if let c = connection(id: id) { LiveActivityController.shared.update(c) }
        }
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
