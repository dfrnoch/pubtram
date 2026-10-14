import SwiftUI

/// Main page: the search card and favorite / recent routes.
struct HomeView: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @State private var previews = RoutePreviews()
    @State private var renaming: SavedRoute?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                SearchCard()
            }

            if !store.favoriteRoutes.isEmpty {
                Section("Oblíbené") {
                    ForEach(store.favoriteRoutes) { route in
                        FavoriteRouteRow(route: route, preview: previews.state(for: route)) {
                            model.apply(route)
                        }
                        .contextMenu { menu(for: route) }
                        .swipeActions {
                            Button("Odebrat", systemImage: "star.slash", role: .destructive) {
                                store.removeFavorite(route)
                            }
                        }
                    }
                    .onMove(perform: store.moveFavoriteRoutes)
                }
            }

            let recents = store.recentRoutes.filter { !store.isFavorite($0) }.prefix(6)
            if !recents.isEmpty {
                Section {
                    ForEach(Array(recents)) { route in
                        RecentRouteRow(route: route) { model.apply(route) }
                            .swipeActions(edge: .leading) {
                                Button("Oblíbit", systemImage: "star.fill") { store.toggleFavorite(route) }
                                    .tint(.yellow)
                            }
                            .swipeActions {
                                Button("Smazat", systemImage: "trash", role: .destructive) { store.removeRecent(route) }
                            }
                            .contextMenu {
                                Button("Přidat do oblíbených", systemImage: "star") { store.toggleFavorite(route) }
                                Button("Hledat opačným směrem", systemImage: "arrow.uturn.left") {
                                    model.apply(route.reversed)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Nedávno hledané")
                        Spacer()
                        Button("Vymazat") { withAnimation { store.clearRecentRoutes() } }
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }

            if store.favoriteRoutes.isEmpty {
                Section {
                    TipRow()
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Spojení")
        .toolbar {
            if store.favoriteRoutes.count > 1 {
                EditButton()
            }
        }
        .task(id: store.favoriteRoutes.map(\.id)) {
            while !Task.isCancelled {
                await previews.refresh(store.favoriteRoutes)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .alert("Přejmenovat trasu", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField("Např. Do práce", text: $renameText)
            Button("Uložit") {
                if let renaming { store.rename(renaming, to: renameText) }
            }
            Button("Zrušit", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func menu(for route: SavedRoute) -> some View {
        Button("Přejmenovat", systemImage: "pencil") {
            renameText = route.name ?? ""
            renaming = route
        }
        Button("Hledat opačným směrem", systemImage: "arrow.uturn.left") {
            model.apply(route.reversed)
        }
        Button("Upravit v hledání", systemImage: "square.and.pencil") {
            model.from = route.from
            model.to = route.to
        }
        Divider()
        Button("Odebrat z oblíbených", systemImage: "star.slash", role: .destructive) {
            store.removeFavorite(route)
        }
    }
}

// MARK: - Rows

private struct FavoriteRouteRow: View {
    let route: SavedRoute
    let preview: RoutePreviews.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(route.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        if route.name != nil {
                            Text(route.placesLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if case .loaded(let c) = preview {
                        TimelineView(.everyMinute) { context in
                            Text(Fmt.countdown(to: c.effectiveDeparture, now: context.date))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                    }
                }
                switch preview {
                case .loaded(let c):
                    HStack(spacing: 8) {
                        Text("\(Fmt.time(c.departure)) – \(Fmt.time(c.arrival))")
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                        JourneyBar(legs: c.legs, height: 16)
                        if let delay = c.maxDelay, Fmt.delayMinutes(delay) > 0 {
                            DelayBadge(delay: delay, compact: true)
                        }
                    }
                    .padding(.leading, 20)
                case .loading:
                    Text("Hledám nejbližší spojení…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                case .failed:
                    EmptyView()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct RecentRouteRow: View {
    let route: SavedRoute
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.from.label).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(route.to.label).lineLimit(1)
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct TipRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tipy", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)
            Label("Hvězdičkou nad výsledky si trasu uložíte – uvidíte tu rovnou nejbližší spoj.", systemImage: "star")
            Label("Tlačítkem ⊕ přidáte další zastávku: hledá se ze všech najednou.", systemImage: "plus.circle")
            Label("Oblíbené trasy můžete mít i ve widgetu na ploše.", systemImage: "square.grid.2x2")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

// MARK: - Previews of the next connection

@MainActor @Observable
final class RoutePreviews {
    enum State { case loading, loaded(Connection), failed }
    private var states: [SavedRoute.ID: State] = [:]

    func state(for route: SavedRoute) -> State { states[route.id] ?? .loading }

    func refresh(_ routes: [SavedRoute]) async {
        await withTaskGroup(of: (String, State).self) { group in
            for route in routes {
                group.addTask {
                    guard let next = try? await PubtranClient.shared.upcomingConnections(for: route, count: 1).first else {
                        return (route.id, .failed)
                    }
                    return (route.id, .loaded(next))
                }
            }
            for await (id, state) in group {
                // Keep a stale preview rather than flashing an error.
                if case .failed = state, case .loaded = states[id] { continue }
                states[id] = state
            }
        }
    }
}
