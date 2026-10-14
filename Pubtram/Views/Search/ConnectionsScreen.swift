import SwiftUI

struct ConnectionsScreen: View {
    @Environment(SearchModel.self) private var model
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SearchSidebar()
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
        } detail: {
            NavigationStack {
                if let id = model.selectedID, model.connection(id: id) != nil {
                    ConnectionDetailView(connectionID: id)
                        .id(id)
                } else {
                    ContentUnavailableView(
                        model.hasResults ? "Vyberte spojení" : "Kam to bude?",
                        systemImage: "tram.fill",
                        description: Text(
                            model.hasResults
                                ? "Detail s mapou a živými informacemi se zobrazí tady."
                                : "Zadejte odkud a kam chcete jet."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SearchSidebar: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @State private var picking: PlaceField?
    @State private var showsTime = false
    @State private var showsOptions = false

    enum PlaceField: String, Identifiable {
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

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedID) {
            Section {
                PlaceFieldsCard(picking: $picking)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                SearchControlsRow(showsTime: $showsTime, showsOptions: $showsOptions)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            if model.hasResults {
                ResultsSection()
            } else if model.isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Hledám spojení…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                SavedRoutesSections()
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Spojení")
        .refreshable {
            if model.hasResults { await model.refreshLive() }
        }
        .sheet(item: $picking) { field in
            PlacePickerView(title: field.title, near: nearPlace(for: field)) { place in
                switch field {
                case .from: model.from = place
                case .to: model.to = place
                case .via: model.via = place
                }
                if model.canSearch { model.search() }
            }
        }
        .sheet(isPresented: $showsTime) {
            TimeSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsOptions) {
            OptionsSheet()
        }
        .onChange(of: store.searchOptions) {
            if model.hasResults { model.search() }
        }
    }

    private func nearPlace(for field: PlaceField) -> Place? {
        switch field {
        case .from: model.to ?? model.from
        case .to, .via: model.from ?? model.to
        }
    }
}

// MARK: - Form

private struct PlaceFieldsCard: View {
    @Environment(SearchModel.self) private var model
    @Binding var picking: SearchSidebar.PlaceField?

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                field(.from, place: model.from, symbol: "circle.circle.fill", tint: .green)
                Divider().padding(.leading, 44)
                if model.showsVia {
                    HStack(spacing: 0) {
                        field(.via, place: model.via, symbol: "smallcircle.filled.circle", tint: .secondary)
                        Button {
                            withAnimation {
                                model.showsVia = false
                                model.via = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Odebrat průjezdní místo")
                    }
                    Divider().padding(.leading, 44)
                }
                field(.to, place: model.to, symbol: "mappin.circle.fill", tint: .red)
            }

            VStack(spacing: 4) {
                Button {
                    withAnimation(.snappy) { model.swap() }
                    if model.canSearch && model.hasResults { model.search() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Prohodit")

                if !model.showsVia {
                    Button {
                        withAnimation { model.showsVia = true }
                    } label: {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Přidat průjezdní místo")
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func field(_ field: SearchSidebar.PlaceField, place: Place?, symbol: String, tint: Color) -> some View {
        Button {
            picking = field
        } label: {
            HStack(spacing: 12) {
                Image(systemName: place?.isCurrentLocation == true ? "location.fill" : symbol)
                    .foregroundStyle(place?.isCurrentLocation == true ? .blue : tint)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(field.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(place?.name ?? "Vyberte místo")
                        .font(.body.weight(place == nil ? .regular : .medium))
                        .foregroundStyle(place == nil ? .tertiary : .primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.leading, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchControlsRow: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @Binding var showsTime: Bool
    @Binding var showsOptions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    showsTime = true
                } label: {
                    Label(timeLabel, systemImage: "clock")
                        .lineLimit(1)
                }
                .buttonStyle(.glass)

                Button {
                    showsOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(height: 20)
                }
                .accessibilityLabel("Možnosti hledání")
                .buttonStyle(.glass)
                .overlay(alignment: .topTrailing) {
                    if !store.searchOptions.isDefault {
                        Circle().fill(.tint).frame(width: 9, height: 9).offset(x: 2, y: -2)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    model.search()
                } label: {
                    if model.isSearching {
                        ProgressView().frame(width: 22)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .frame(width: 22)
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!model.canSearch || model.isSearching)
                .accessibilityLabel("Vyhledat")
            }
            if let summary = store.searchOptions.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeLabel: String {
        guard let date = model.date else { return model.isDeparture ? "Odjezd teď" : "Příjezd teď" }
        let kind = model.isDeparture ? "Odj." : "Příj."
        let day = Fmt.day(date)
        return "\(kind) \(day == "dnes" ? "" : day + " ")\(Fmt.time(date))"
    }
}

// MARK: - Results

private struct ResultsSection: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store

    var body: some View {
        Section {
            pagingButton("Dřívější spojení", systemImage: "chevron.up", loading: model.isLoadingEarlier) {
                await model.loadEarlier()
            }
            ForEach(model.connections) { connection in
                ConnectionRow(connection: connection, isSelected: model.selectedID == connection.id)
                    .tag(connection.id)
            }
            pagingButton("Další spojení", systemImage: "chevron.down", loading: model.isLoadingLater) {
                await model.loadLater()
            }
        } header: {
            if let route = model.searchedRoute {
                HStack {
                    Text("\(route.from.name) → \(route.to.name)")
                        .lineLimit(1)
                    Spacer()
                    Button {
                        store.toggleFavorite(route)
                    } label: {
                        Image(systemName: store.isFavorite(route) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .accessibilityLabel(store.isFavorite(route) ? "Odebrat z oblíbených" : "Přidat do oblíbených")
                }
            }
        } footer: {
            if let error = model.error {
                Text(error)
            }
        }
    }

    private func pagingButton(
        _ title: String, systemImage: String, loading: Bool, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Spacer()
                if loading {
                    ProgressView()
                } else {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
            }
        }
        .disabled(loading)
    }
}

private struct SavedRoutesSections: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store

    var body: some View {
        if !store.favoriteRoutes.isEmpty {
            Section("Oblíbené trasy") {
                ForEach(store.favoriteRoutes) { route in
                    routeRow(route, favorite: true)
                }
                .onDelete(perform: store.removeFavoriteRoutes)
                .onMove(perform: store.moveFavoriteRoutes)
            }
        }
        if !store.recentRoutes.isEmpty {
            Section("Nedávno hledané") {
                ForEach(store.recentRoutes) { route in
                    routeRow(route, favorite: false)
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleFavorite(route)
                            } label: {
                                Label("Oblíbené", systemImage: "star.fill")
                            }
                            .tint(.yellow)
                        }
                }
                .onDelete(perform: store.removeRecentRoutes)
            }
        }
        if store.favoriteRoutes.isEmpty && store.recentRoutes.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tip", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                    Text("Trasy, které často jezdíte, si uložte hvězdičkou nad výsledky. Budou pak tady na jedno klepnutí.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func routeRow(_ route: SavedRoute, favorite: Bool) -> some View {
        Button {
            model.apply(route)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: favorite ? "star.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(favorite ? .yellow : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.from.name).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(route.to.name).lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
