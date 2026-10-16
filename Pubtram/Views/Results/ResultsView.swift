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
                ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                    Section {
                        ForEach(group.connections) { connection in
                            row(connection)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            if index == 0 { earlierButton }
                        }
                    }
                }

                if model.canLoadLater && model.lineFilter.isEmpty {
                    Section {
                        PagingRow(title: "Další spojení", systemImage: "arrow.down", isLoading: model.isLoadingLater) {
                            Task { await model.loadLater() }
                        }
                        .onAppear { Task { await model.loadLater() } }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(model.searchedRoute?.compactLabel ?? "Spojení")
        .navigationSubtitle(subtitle)
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
    private var earlierButton: some View {
        if model.isLoadingEarlier {
            ProgressView().controlSize(.small)
        } else {
            Button {
                Task { await model.loadEarlier() }
            } label: {
                Label("Dřívější", systemImage: "arrow.up")
                    .labelStyle(.chip)
                    .font(.subheadline.weight(.medium))
                    .textCase(nil)
            }
            .buttonStyle(.borderless)
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
                .navigationLinkIndicatorVisibility(.hidden)
        }
    }

    /// Time plus any active filters, shown under the title.
    private var subtitle: String {
        var parts = [TimeLabel.text(date: model.date, isDeparture: model.isDeparture)]
        if model.sort != .departure { parts.append(model.sort.shortTitle) }
        if !model.lineFilter.isEmpty {
            let lines = model.lineFilter.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            parts.append((lines.count == 1 ? "linka " : "linky ") + lines.joined(separator: ", "))
        }
        if let summary = store.searchOptions.summary { parts.append(summary) }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            FilterMenu(showsTime: $showsTime, showsOptions: $showsOptions)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
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

/// Everything that shapes the results – time, sorting, lines, options – behind one toolbar button.
private struct FilterMenu: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @Binding var showsTime: Bool
    @Binding var showsOptions: Bool

    var body: some View {
        @Bindable var model = model
        @Bindable var store = store
        Menu {
            Section("Čas") {
                Button("Odjezd teď", systemImage: "clock.arrow.circlepath") { setTime(nil) }
                Menu("Později", systemImage: "clock") {
                    Button("Za 15 minut") { setTime(15) }
                    Button("Za 30 minut") { setTime(30) }
                    Button("Za hodinu") { setTime(60) }
                    Button("Za 2 hodiny") { setTime(120) }
                }
                Button("Vybrat čas…", systemImage: "calendar") { showsTime = true }
            }

            Section {
                Picker(selection: $model.sort) {
                    ForEach(SearchModel.Sort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                } label: {
                    Label("Řazení", systemImage: "arrow.up.arrow.down")
                    Text(model.sort.title)
                }
                .pickerStyle(.menu)

                if model.availableLines.count > 1 {
                    Menu {
                        LineFilterMenuItems(lines: model.availableLines, selection: $model.lineFilter)
                    } label: {
                        Label("Linky", systemImage: "tram")
                        Text(linesTitle)
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            }

            Section("Pohodlí") {
                Toggle(isOn: $store.searchOptions.lowFloor) { Label("Bezbariérově", systemImage: "figure.roll") }
                Toggle(isOn: $store.searchOptions.stroller) { Label("S kočárkem", systemImage: "stroller.fill") }
                Toggle(isOn: $store.searchOptions.bike) { Label("S kolem", systemImage: "bicycle") }
                Toggle(isOn: $store.searchOptions.airCondition) { Label("Klimatizace", systemImage: "snowflake") }
                Button("Všechny možnosti…", systemImage: "slider.horizontal.3") { showsOptions = true }
            }
        } label: {
            Label(
                "Filtry",
                systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
    }

    private var isFiltered: Bool {
        model.sort != .departure || !model.lineFilter.isEmpty || !store.searchOptions.isDefault
    }

    /// Departure in `minutes` from now, or now when `nil`.
    private func setTime(_ minutes: Double?) {
        model.date = minutes.map { Date.now.addingTimeInterval($0 * 60) }
        model.isDeparture = true
        model.search()
    }

    private var linesTitle: String {
        guard !model.lineFilter.isEmpty else { return "Všechny" }
        return model.lineFilter.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", ")
    }
}

/// Toggles for a multi-select line filter inside a `Menu`.
struct LineFilterMenuItems: View {
    let lines: [(line: String, vehicle: VehicleType)]
    @Binding var selection: Set<String>

    var body: some View {
        if !selection.isEmpty {
            Button("Zobrazit všechny linky", systemImage: "arrow.counterclockwise") { selection = [] }
        }
        Section("Linky") {
            ForEach(lines, id: \.line) { item in
                Toggle(isOn: Binding(
                    get: { selection.contains(item.line) },
                    set: { on in
                        if on { selection.insert(item.line) } else { selection.remove(item.line) }
                    }
                )) {
                    Label("\(item.vehicle.name) \(item.line)", systemImage: item.vehicle.symbol)
                }
            }
        }
    }
}

/// Small text button for loading earlier connections, styled like a list footer action.
private struct PagingRow: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.chip)
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .frame(minHeight: 28)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
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
