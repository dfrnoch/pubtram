import Foundation
import Observation

/// Navigation and preview cache for the departures tab.
@MainActor @Observable
final class BoardsModel {
    /// Board shown in the detail column (saved or ad-hoc from a stop search).
    var selected: SavedBoard?
    private(set) var previews: [SavedBoard.ID: [Departure]] = [:]

    func refreshPreviews(_ boards: [SavedBoard]) async {
        await withTaskGroup(of: (String, [Departure]?).self) { group in
            for board in boards {
                group.addTask {
                    (board.id, try? await PubtranClient.shared.departures(for: board, count: 12))
                }
            }
            for await (id, departures) in group {
                if let departures { previews[id] = departures }
            }
        }
    }
}

/// State of a single departure board screen.
@MainActor @Observable
final class BoardDetailModel {
    let board: SavedBoard
    var lineFilter: Set<String>
    private(set) var departures: [Departure] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var lastUpdate: Date?

    init(board: SavedBoard) {
        self.board = board
        lineFilter = Set(board.lines)
    }

    /// The board without its own line restriction, so all lines can be offered as filters.
    private var unrestricted: SavedBoard { SavedBoard(stops: board.stops, lines: [], name: board.name) }

    var lines: [(line: String, vehicle: VehicleType)] {
        var seen = Set<String>()
        return departures.compactMap { d in seen.insert(d.displayLine).inserted ? (d.displayLine, d.vehicle) : nil }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
    }

    var visibleDepartures: [Departure] {
        let upcoming = departures.filter { $0.time > .now.addingTimeInterval(-60) }
        guard !lineFilter.isEmpty else { return upcoming }
        return upcoming.filter { lineFilter.contains($0.displayLine) || lineFilter.contains($0.line) }
    }

    func reload() async {
        isLoading = departures.isEmpty
        defer { isLoading = false }
        do {
            departures = try await PubtranClient.shared.departures(for: unrestricted)
            error = nil
            lastUpdate = .now
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let last = departures.last, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let more = try? await PubtranClient.shared.departures(for: unrestricted, after: last.time) else { return }
        let known = Set(departures.map(\.id))
        departures += more.filter { !known.contains($0.id) }
    }
}
