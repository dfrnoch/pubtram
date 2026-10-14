import SwiftUI

/// From / (via) / To fields with optional alternatives ("Anděl nebo Na Knížecí"),
/// time & options chips and the search button.
struct SearchCard: View {
    @Environment(SearchModel.self) private var model
    @Environment(AppStore.self) private var store
    @State private var picking: PickRequest?
    @State private var showsTime = false
    @State private var showsOptions = false

    struct PickRequest: Identifiable {
        let field: PlaceField
        /// `nil` adds an alternative place.
        let index: Int?
        var id: String { "\(field.rawValue)-\(index.map(String.init) ?? "new")" }

        var title: String {
            switch (field, index) {
            case (.from, nil): "Další výchozí místo"
            case (.to, nil): "Další cíl"
            default: field.title
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    fieldGroup(.from)
                    Divider().padding(.leading, 44)
                    if model.showsVia {
                        fieldGroup(.via)
                        Divider().padding(.leading, 44)
                    }
                    fieldGroup(.to)
                }
                Button {
                    withAnimation(.snappy) { model.swap() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Prohodit odkud a kam")
                .padding(.leading, 4)
            }

            controls

            Button {
                model.search()
            } label: {
                Label("Vyhledat spojení", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canSearch)
        }
        .padding(.vertical, 6)
        .sheet(item: $picking) { request in
            PlacePickerView(
                title: request.title,
                near: (model.from + model.to).first { !$0.isCurrentLocation },
                excluded: request.index == nil ? model.places(for: request.field) : []
            ) { place in
                withAnimation { model.set(place, for: request.field, at: request.index) }
            }
        }
        .sheet(isPresented: $showsTime) {
            TimeSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsOptions) {
            OptionsSheet()
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func fieldGroup(_ field: PlaceField) -> some View {
        let places = model.places(for: field)
        VStack(spacing: 0) {
            primaryRow(field, place: places.first, count: places.count)
            ForEach(Array(places.enumerated().dropFirst()), id: \.element.id) { index, place in
                alternativeRow(field, index: index, place: place)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func primaryRow(_ field: PlaceField, place: Place?, count: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                picking = PickRequest(field: field, index: 0)
            } label: {
                HStack(spacing: 12) {
                    icon(for: field, place: place)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(field.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(place?.name ?? placeholder(field))
                            .font(.body.weight(place == nil ? .regular : .medium))
                            .foregroundStyle(place == nil ? .tertiary : .primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if field == .via {
                Button {
                    withAnimation { model.remove(at: 0, from: .via) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Odebrat průjezdní místo")
            } else if place != nil, count < MultiSearch.maxPlacesPerSide {
                Button {
                    picking = PickRequest(field: field, index: nil)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(field == .from ? "Přidat další výchozí místo" : "Přidat další cíl")
            }
        }
    }

    private func alternativeRow(_ field: PlaceField, index: Int, place: Place) -> some View {
        HStack(spacing: 12) {
            Text("nebo")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(width: 28)
            Button {
                picking = PickRequest(field: field, index: index)
            } label: {
                HStack {
                    Text(place.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                withAnimation { model.remove(at: index, from: field) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Odebrat \(place.name)")
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func icon(for field: PlaceField, place: Place?) -> some View {
        if place?.isCurrentLocation == true {
            Image(systemName: "location.fill").foregroundStyle(.blue).font(.title3)
        } else {
            switch field {
            case .from: Image(systemName: "circle.circle.fill").foregroundStyle(.green).font(.title3)
            case .to: Image(systemName: "mappin.circle.fill").foregroundStyle(.red).font(.title3)
            case .via: Image(systemName: "smallcircle.filled.circle").foregroundStyle(.secondary).font(.title3)
            }
        }
    }

    private func placeholder(_ field: PlaceField) -> String {
        switch field {
        case .from: "Zastávka, adresa nebo poloha"
        case .to: "Kam jedete?"
        case .via: "Průjezdní zastávka"
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    showsTime = true
                } label: {
                    Label(TimeLabel.text(date: model.date, isDeparture: model.isDeparture), systemImage: "clock")
                        .lineLimit(1)
                }
                .buttonStyle(.glass)

                Button {
                    showsOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3").frame(height: 20)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Možnosti hledání")
                .overlay(alignment: .topTrailing) {
                    if !store.searchOptions.isDefault {
                        Circle().fill(.tint).frame(width: 9, height: 9).offset(x: 1, y: -1)
                    }
                }

                if !model.showsVia {
                    Button {
                        withAnimation { model.showsVia = true }
                        picking = PickRequest(field: .via, index: 0)
                    } label: {
                        Label("Přes", systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                    }
                    .buttonStyle(.glass)
                }
                Spacer(minLength: 0)
            }
            if let summary = store.searchOptions.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum TimeLabel {
    static func text(date: Date?, isDeparture: Bool) -> String {
        guard let date else { return isDeparture ? "Odjezd teď" : "Příjezd teď" }
        let day = Fmt.day(date)
        let when = day == "dnes" ? Fmt.time(date) : "\(day) \(Fmt.time(date))"
        // Departure is the default, so only arrival needs spelling out.
        if isDeparture { return day == "dnes" ? "Odjezd \(when)" : when.prefix(1).uppercased() + when.dropFirst() }
        return "Příjezd \(when)"
    }
}
