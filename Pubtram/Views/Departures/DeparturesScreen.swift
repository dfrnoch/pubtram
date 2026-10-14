import SwiftUI

struct DeparturesScreen: View {
    @Environment(DeparturesModel.self) private var model
    @Environment(AppStore.self) private var store
    @State private var showsPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if let stop = model.stop {
                    DepartureBoard(stop: stop)
                } else {
                    StopChooser(showsPicker: $showsPicker)
                }
            }
            .navigationTitle(model.stop?.name ?? "Odjezdy")
            .toolbar {
                if let stop = model.stop {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zastávky", systemImage: "list.bullet") { model.stop = nil }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.toggleFavorite(stop: stop)
                        } label: {
                            Label(
                                "Oblíbená",
                                systemImage: store.isFavorite(stop: stop) ? "star.fill" : "star")
                        }
                        .tint(.yellow)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Hledat zastávku", systemImage: "magnifyingglass") { showsPicker = true }
                }
            }
            .sheet(isPresented: $showsPicker) {
                PlacePickerView(title: "Zastávka", kind: .stops, allowsCurrentLocation: false) { place in
                    model.stop = place
                    store.addRecent(place: place)
                }
            }
        }
    }
}

private struct StopChooser: View {
    @Environment(DeparturesModel.self) private var model
    @Environment(AppStore.self) private var store
    @Binding var showsPicker: Bool

    private var recentStops: [Place] {
        store.recentPlaces.filter { $0.isStop && !store.isFavorite(stop: $0) }
    }

    var body: some View {
        if store.favoriteStops.isEmpty && recentStops.isEmpty {
            ContentUnavailableView {
                Label("Odjezdová tabule", systemImage: "clock.badge.checkmark.fill")
            } description: {
                Text("Najděte zastávku a uvidíte, co z ní jede v nejbližších minutách.")
            } actions: {
                Button("Vybrat zastávku") { showsPicker = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            List {
                if !store.favoriteStops.isEmpty {
                    Section("Oblíbené zastávky") {
                        ForEach(store.favoriteStops) { stop in
                            Button { model.stop = stop } label: { PlaceRow(place: stop) }
                        }
                        .onDelete(perform: store.removeFavoriteStops)
                    }
                }
                if !recentStops.isEmpty {
                    Section("Nedávné") {
                        ForEach(recentStops) { stop in
                            Button { model.stop = stop } label: { PlaceRow(place: stop) }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.toggleFavorite(stop: stop)
                                    } label: {
                                        Label("Oblíbená", systemImage: "star.fill")
                                    }
                                    .tint(.yellow)
                                }
                        }
                    }
                }
            }
        }
    }
}

private struct DepartureBoard: View {
    let stop: Place
    @Environment(DeparturesModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 15)) { context in
            List {
                if model.lines.count > 1 {
                    Section {
                        LineFilter(lines: model.lines, selection: $model.lineFilter)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if model.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
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
        .refreshable { await model.reload() }
        .task(id: stop.id) {
            while !Task.isCancelled {
                await model.reload()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

private struct LineFilter: View {
    let lines: [(line: String, vehicle: VehicleType)]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selection = nil
                } label: {
                    Text("Vše")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .tint(selection == nil ? .accentColor : nil)

                ForEach(lines, id: \.line) { item in
                    Button {
                        selection = selection == item.line ? nil : item.line
                    } label: {
                        LineBadge(vehicle: item.vehicle, line: item.line, size: .small)
                            .opacity(selection == nil || selection == item.line ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
            Text(departure.destination)
                .font(.body.weight(.medium))
                .lineLimit(2)
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
