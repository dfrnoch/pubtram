import CoreLocation
import SwiftUI

struct PlacePickerView: View {
    let title: String
    var near: Place?
    var kind: PubtranClient.SuggestKind = .any
    var allowsCurrentLocation = true
    /// Places already chosen for this field – hidden from the lists.
    var excluded: [Place] = []
    let onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    if allowsCurrentLocation && !excluded.contains(where: \.isCurrentLocation) {
                        Button {
                            pick(.currentLocation(CLLocationCoordinate2D()))
                        } label: {
                            PlaceRow(place: .currentLocation(CLLocationCoordinate2D()))
                        }
                    }
                    if !recents.isEmpty {
                        Section("Nedávné") {
                            ForEach(recents) { place in
                                Button { pick(place) } label: { PlaceRow(place: place) }
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView(error, systemImage: "wifi.exclamationmark")
                        .listRowSeparator(.hidden)
                } else if results.isEmpty && !isLoading {
                    ContentUnavailableView.search(text: trimmedQuery)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(results.filter { !isExcluded($0) }) { place in
                        Button { pick(place) } label: { PlaceRow(place: place) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task(id: trimmedQuery) {
                await fetch()
            }
            .onAppear { focused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(title, text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let first = results.first(where: { !isExcluded($0) }) { pick(first) }
                    }
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if !query.isEmpty {
                    Button("Smazat", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Zrušit") { dismiss() }
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var recents: [Place] {
        (kind == .stops ? store.recentPlaces.filter(\.isStop) : store.recentPlaces).filter { !isExcluded($0) }
    }

    private func isExcluded(_ place: Place) -> Bool {
        excluded.contains { $0.id == place.id }
    }

    private func fetch() async {
        let phrase = trimmedQuery
        guard !phrase.isEmpty else {
            results = []
            error = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await PubtranClient.shared.suggest(phrase, near: near?.coordinate, kind: kind)
            guard !Task.isCancelled else { return }
            results = found
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Nepodařilo se načíst návrhy."
        }
    }

    private func pick(_ place: Place) {
        onPick(place)
        dismiss()
    }
}

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 14) {
            PlaceIcon(place: place)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    ForEach(place.stopModes.dropFirst(), id: \.self) { mode in
                        ModeBadge(mode: mode)
                    }
                }
                if let subtitle = place.shortSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

/// Rounded tile with a white symbol, colored by place type (like Settings icons).
struct PlaceIcon: View {
    let place: Place

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color.gradient, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if let mode = place.stopModes.first { return mode.symbol }
        return place.symbol
    }

    private var color: Color {
        if place.isCurrentLocation { return .blue }
        if let mode = place.stopModes.first { return mode.baseColor }
        switch place.source {
        case "pubt": return .teal
        case "muni", "area": return .indigo
        case "firm", "poi": return .orange
        default: return Color(.systemGray)
        }
    }
}

/// Tiny tile for an additional mode serving a stop.
private struct ModeBadge: View {
    let mode: VehicleType

    var body: some View {
        Image(systemName: mode.symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(mode.baseColor, in: .rect(cornerRadius: 4))
            .accessibilityLabel(mode.name)
    }
}
