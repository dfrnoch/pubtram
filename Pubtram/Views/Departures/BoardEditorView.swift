import SwiftUI

/// Create or edit a departure board: name, one or more stops, optional line filter.
struct BoardEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(SavedBoard)
        var id: String {
            switch self {
            case .create: "create"
            case .edit(let b): b.id
            }
        }
    }

    let mode: Mode
    let onSave: (SavedBoard) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var stops: [Place] = []
    @State private var lines: Set<String> = []
    @State private var availableLines: [(line: String, vehicle: VehicleType)] = []
    @State private var showsPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Název (nepovinný)", text: $name)
                }

                Section {
                    ForEach(stops) { stop in
                        PlaceRow(place: stop)
                    }
                    .onDelete { stops.remove(atOffsets: $0) }
                    Button("Přidat zastávku", systemImage: "plus.circle.fill") { showsPicker = true }
                } header: {
                    Text("Zastávky")
                } footer: {
                    Text("Odjezdy ze všech zastávek se zobrazí na jedné tabuli.")
                }

                if !availableLines.isEmpty {
                    Section {
                        LineGrid(lines: availableLines, selection: $lines)
                    } header: {
                        Text("Linky")
                    } footer: {
                        Text(lines.isEmpty ? "Zobrazují se všechny linky. Klepnutím vyberte jen ty, které vás zajímají." : "Zobrazí se jen vybrané linky.")
                    }
                }

                if case .edit(let board) = mode {
                    Section {
                        Button("Smazat tabuli", role: .destructive) {
                            store.remove(board)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isCreating ? "Nová tabule" : "Upravit tabuli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", systemImage: "checkmark") { save() }
                        .disabled(stops.isEmpty)
                }
            }
            .sheet(isPresented: $showsPicker) {
                PlacePickerView(title: "Přidat zastávku", kind: .stops, allowsCurrentLocation: false, excluded: stops) { place in
                    stops.append(place)
                    store.addRecent(place: place)
                }
            }
            .task(id: stops.map(\.id)) { await loadLines() }
            .onAppear(perform: prefill)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { true } else { false }
    }

    private func prefill() {
        guard case .edit(let board) = mode, stops.isEmpty else { return }
        name = board.name ?? ""
        stops = board.stops
        lines = Set(board.lines)
    }

    private func loadLines() async {
        guard !stops.isEmpty else {
            availableLines = []
            return
        }
        let departures = (try? await PubtranClient.shared.departures(for: SavedBoard(stops: stops), count: 60)) ?? []
        var seen = Set<String>()
        availableLines = departures.compactMap { d in seen.insert(d.displayLine).inserted ? (d.displayLine, d.vehicle) : nil }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
        // Keep previously selected lines visible even if they don't run right now.
        for line in lines where !seen.contains(line) {
            availableLines.append((line, .bus))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = SavedBoard(stops: stops, lines: lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, name: trimmed.isEmpty ? nil : trimmed)
        if case .edit(let original) = mode {
            store.save(board, replacing: original)
        } else {
            store.save(board)
        }
        onSave(board)
        dismiss()
    }
}

private struct LineGrid: View {
    let lines: [(line: String, vehicle: VehicleType)]
    @Binding var selection: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
            ForEach(lines, id: \.line) { item in
                Button {
                    if selection.contains(item.line) { selection.remove(item.line) } else { selection.insert(item.line) }
                } label: {
                    LineBadge(vehicle: item.vehicle, line: item.line)
                        .opacity(selection.isEmpty || selection.contains(item.line) ? 1 : 0.35)
                        .overlay(alignment: .topTrailing) {
                            if selection.contains(item.line) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white, .tint)
                                    .offset(x: 6, y: -6)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
