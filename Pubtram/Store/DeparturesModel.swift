import Foundation
import Observation

@MainActor @Observable
final class DeparturesModel {
    var stop: Place? {
        didSet {
            guard stop != oldValue else { return }
            departures = []
            lineFilter = nil
            error = nil
        }
    }
    var lineFilter: String?
    private(set) var departures: [Departure] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var lastUpdate: Date?

    private let client: PubtranClient

    init(client: PubtranClient = .shared) {
        self.client = client
    }

    var lines: [(line: String, vehicle: VehicleType)] {
        var seen = Set<String>()
        return departures.compactMap { d in seen.insert(d.line).inserted ? (d.line, d.vehicle) : nil }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
    }

    var visibleDepartures: [Departure] {
        let upcoming = departures.filter { $0.time > .now.addingTimeInterval(-60) }
        guard let lineFilter else { return upcoming }
        return upcoming.filter { $0.line == lineFilter }
    }

    func reload() async {
        guard let stop else { return }
        isLoading = departures.isEmpty
        defer { isLoading = false }
        do {
            let result = try await client.departures(from: stop, after: .now.addingTimeInterval(-60))
            guard stop == self.stop else { return }
            departures = result
            error = nil
            lastUpdate = .now
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let stop, let last = departures.last, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let more = try? await client.departures(from: stop, after: last.time) else { return }
        let known = Set(departures.map(\.id))
        departures.append(contentsOf: more.filter { !known.contains($0.id) })
    }
}
