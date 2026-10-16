import SwiftUI

struct BoardDetailView: View {
    let board: SavedBoard
    let onEdit: (SavedBoard) -> Void
    @Environment(AppStore.self) private var store
    @State private var model: BoardDetailModel

    init(board: SavedBoard, onEdit: @escaping (SavedBoard) -> Void) {
        self.board = board
        self.onEdit = onEdit
        _model = State(initialValue: BoardDetailModel(board: board))
    }

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 15)) { context in
            List {
                Section {
                    if model.isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if let error = model.error, model.departures.isEmpty {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else if model.visibleDepartures.isEmpty {
                        Text("V nejbližší době odsud nic nejede.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.visibleDepartures) { departure in
                        DepartureRow(departure: departure, now: context.date)
                    }
                    if !model.departures.isEmpty {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if model.isLoadingMore {
                                    ProgressView()
                                } else {
                                    Label("Další odjezdy", systemImage: "chevron.down")
                                        .font(.subheadline.weight(.medium))
                                }
                                Spacer()
                            }
                        }
                    }
                } footer: {
                    if let update = model.lastUpdate {
                        Text("Aktualizováno v \(Fmt.time(update)) · obnovuje se automaticky")
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            if model.lines.count > 1 {
                LineFilterChips(lines: model.lines, selection: $model.lineFilter)
            }
        }
        .navigationTitle(board.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let saved = store.savedBoard(matching: board) {
                    Button("Upravit", systemImage: "slider.horizontal.3") { onEdit(saved) }
                } else {
                    Button {
                        store.save(SavedBoard(stops: board.stops, lines: Array(model.lineFilter).sorted()))
                    } label: {
                        Label("Uložit", systemImage: "star")
                    }
                    .tint(.yellow)
                }
            }
        }
        .refreshable { await model.reload() }
        .task(id: board.id) {
            while !Task.isCancelled {
                await model.reload()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct DepartureRow: View {
    let departure: Departure
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(vehicle: departure.vehicle, line: departure.line)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(departure.destination)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let stop = departure.stopName {
                    Text("z \(stop)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.countdown(to: departure.time, now: now))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(soon ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(Fmt.time(departure.time))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var soon: Bool { departure.time.timeIntervalSince(now) < 5 * 60 }
}
