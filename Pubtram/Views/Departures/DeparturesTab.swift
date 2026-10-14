import SwiftUI

/// Saved departure boards with live previews → board detail.
struct DeparturesTab: View {
    @Environment(BoardsModel.self) private var boards
    @Environment(AppStore.self) private var store
    @State private var showsPicker = false
    @State private var editing: BoardEditorView.Mode?

    var body: some View {
        @Bindable var boards = boards
        NavigationSplitView {
            List(selection: $boards.selected) {
                if store.boards.isEmpty {
                    EmptyBoardsView(showsPicker: $showsPicker, editing: $editing)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.boards) { board in
                            BoardCard(board: board, departures: boards.previews[board.id])
                                .tag(board)
                                .contextMenu {
                                    Button("Upravit", systemImage: "pencil") { editing = .edit(board) }
                                    Button("Smazat", systemImage: "trash", role: .destructive) { store.remove(board) }
                                }
                        }
                        .onDelete(perform: store.removeBoards)
                        .onMove(perform: store.moveBoards)
                    } footer: {
                        Text("Tabule může spojovat víc zastávek a jen vybrané linky – třeba obě zastávky, odkud vám jede tramvaj domů.")
                    }
                }
            }
            .navigationTitle("Odjezdy")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Najít zastávku", systemImage: "magnifyingglass") { showsPicker = true }
                        Button("Nová tabule…", systemImage: "rectangle.stack.badge.plus") { editing = .create }
                    } label: {
                        Label("Přidat", systemImage: "plus")
                    }
                }
            }
            .task(id: store.boards.map(\.id)) {
                while !Task.isCancelled {
                    await boards.refreshPreviews(store.boards)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        } detail: {
            NavigationStack {
                if let board = boards.selected {
                    BoardDetailView(board: board) { editing = .edit($0) }
                        .id(board.id)
                } else {
                    ContentUnavailableView(
                        "Vyberte zastávku", systemImage: "clock.badge.checkmark.fill",
                        description: Text("Uvidíte, co z ní jede v nejbližších minutách."))
                }
            }
        }
        .sheet(isPresented: $showsPicker) {
            PlacePickerView(title: "Zastávka", kind: .stops, allowsCurrentLocation: false) { place in
                store.addRecent(place: place)
                boards.selected = SavedBoard(stops: [place])
            }
        }
        .sheet(item: $editing) { mode in
            BoardEditorView(mode: mode) { saved in
                boards.selected = saved
            }
        }
    }
}

private struct EmptyBoardsView: View {
    @Binding var showsPicker: Bool
    @Binding var editing: BoardEditorView.Mode?

    var body: some View {
        ContentUnavailableView {
            Label("Odjezdové tabule", systemImage: "clock.badge.checkmark.fill")
        } description: {
            Text("Uložte si zastávky, ze kterých jezdíte. Jedna tabule může spojit víc zastávek a jen vybrané linky.")
        } actions: {
            Button("Najít zastávku") { showsPicker = true }
                .buttonStyle(.glassProminent)
            Button("Vytvořit tabuli") { editing = .create }
                .buttonStyle(.glass)
        }
    }
}

/// Saved board with its next departures.
private struct BoardCard: View {
    let board: SavedBoard
    let departures: [Departure]?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: board.stops.count > 1 ? "signpost.right.and.left.fill" : "signpost.right.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(board.title).font(.headline)
                        if let subtitle = board.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if let departures {
                    let upcoming = departures.filter { $0.time > context.date.addingTimeInterval(-30) }.prefix(3)
                    if upcoming.isEmpty {
                        Text("V nejbližší době nic nejede").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(upcoming)) { d in
                        HStack(spacing: 8) {
                            LineBadge(vehicle: d.vehicle, line: d.line, size: .small)
                                .frame(minWidth: 44, alignment: .leading)
                            Text(d.destination).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Fmt.countdown(to: d.time, now: context.date))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
