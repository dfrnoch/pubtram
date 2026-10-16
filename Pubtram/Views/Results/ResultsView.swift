import SwiftUI

/// Search results: grouped by day, sortable, filterable by line, with infinite scrolling.
struct ResultsView: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    /// iPhone pushes the detail; iPad selects it in the split view's detail column.
    var pushesDetail = true
    @State private var showsTime = false
    @State private var showsOptions = false

    private var usesSelection: Bool { !pushesDetail }

    var body: some View {
        @Bindable var model = model
        List(selection: usesSelection ? $model.selectedID : .constant(nil)) {
            Section {
                QueryChips(showsTime: $showsTime, showsOptions: $showsOptions)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            if model.availableLines.count > 1 {
                Section {
                    LineFilterChips(lines: model.availableLines, selection: $model.lineFilter)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if model.isSearching && !model.hasResults {
                Section {
                    SearchingRow(pairCount: max(1, model.from.count * model.to.count))
                }
            } else if let error = model.error, !model.hasResults {
                Section {
                    ContentUnavailableView {
                        Label("Nic jsme nenašli", systemImage: "tram")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Zkusit znovu") { model.search() }
                    }
                }
            } else {
                Section {
                    PagingRow(title: "Dřívější spojení", systemImage: "chevron.up", isLoading: model.isLoadingEarlier) {
                        Task { await model.loadEarlier() }
                    }
                }

                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.connections) { connection in
                            row(connection)
                        }
                    }
                }

                if model.canLoadLater && model.lineFilter.isEmpty {
                    Section {
                        PagingRow(title: "Další spojení", systemImage: "chevron.down", isLoading: model.isLoadingLater) {
                            Task { await model.loadLater() }
                        }
                        .onAppear { Task { await model.loadLater() } }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(model.searchedRoute?.compactLabel ?? "Spojení")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable { await model.refreshLive() }
        .onChange(of: store.searchOptions) { model.search() }
        .sheet(isPresented: $showsTime) {
            TimeSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsOptions) {
            OptionsSheet()
        }
    }

    @ViewBuilder
    private func row(_ connection: Connection) -> some View {
        let content = ConnectionRow(
            connection: connection,
            isSelected: usesSelection && model.selectedID == connection.id,
            isFastest: connection.id == model.fastestID,
            showsDestination: model.to.count > 1)
        if usesSelection {
            content.tag(connection.id)
        } else {
            NavigationLink(value: SearchDestination.connection(connection.id)) { content }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let route = model.searchedRoute {
                Button {
                    store.toggleFavorite(route)
                } label: {
                    Label(
                        store.isFavorite(route) ? "Odebrat z oblíbených" : "Přidat do oblíbených",
                        systemImage: store.isFavorite(route) ? "star.fill" : "star")
                }
                .tint(.yellow)
            }
        }
    }

    private struct DayGroup {
        let title: String
        let connections: [Connection]
    }

    /// Day sections when sorted chronologically (long searches often cross midnight).
    private var groups: [DayGroup] {
        let visible = model.visibleConnections
        guard model.sort == .departure else { return [DayGroup(title: "", connections: visible)] }
        var result: [DayGroup] = []
        for connection in visible {
            let day = Fmt.day(connection.departure)
            let title = day == "dnes" ? "Dnes" : day.prefix(1).uppercased() + day.dropFirst()
            if result.last?.title == title {
                result[result.count - 1] = DayGroup(title: title, connections: result[result.count - 1].connections + [connection])
            } else {
                result.append(DayGroup(title: title, connections: [connection]))
            }
        }
        // A single "today" header adds nothing.
        if result.count == 1 && result[0].title == "Dnes" { return [DayGroup(title: "", connections: visible)] }
        return result
    }
}

// MARK: - Pieces

private struct QueryChips: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @Binding var showsTime: Bool
    @Binding var showsOptions: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showsTime = true
                } label: {
                    Label(TimeLabel.text(date: model.date, isDeparture: model.isDeparture), systemImage: "clock")
                }
                .buttonStyle(.glass)

                Button {
                    showsOptions = true
                } label: {
                    Label(store.searchOptions.summary ?? "Možnosti", systemImage: "slider.horizontal.3")
                        .lineLimit(1)
                }
                .buttonStyle(.glass)

                Menu {
                    Picker("Řazení", selection: Bindable(model).sort) {
                        ForEach(SearchModel.Sort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                } label: {
                    Label(model.sort == .departure ? "Řazení" : model.sort.title, systemImage: "arrow.up.arrow.down")
                        .lineLimit(1)
                }
                .buttonStyle(.glass)

            }
            .labelStyle(.chip)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}

struct LineFilterChips: View {
    let lines: [(line: String, vehicle: VehicleType)]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selection = []
                } label: {
                    Text("Všechny linky")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(selection.isEmpty ? .accentColor : nil)

                ForEach(lines, id: \.line) { item in
                    let active = selection.isEmpty || selection.contains(item.line)
                    Button {
                        if selection.contains(item.line) {
                            selection.remove(item.line)
                        } else {
                            selection.insert(item.line)
                        }
                    } label: {
                        LineBadge(vehicle: item.vehicle, line: item.line)
                            .opacity(active ? 1 : 0.35)
                            .overlay(alignment: .topTrailing) {
                                if selection.contains(item.line) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.white, .tint)
                                        .offset(x: 5, y: -5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(item.line) ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

private struct PagingRow: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.chip)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
            }
        }
        .disabled(isLoading)
    }
}

private struct SearchingRow: View {
    let pairCount: Int

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(pairCount > 1 ? "Prohledávám \(pairCount) kombinace zastávek…" : "Hledám spojení…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
