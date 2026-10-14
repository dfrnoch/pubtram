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
                    Label(error, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty && !isLoading {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else {
                    ForEach(results.filter { !isExcluded($0) }) { place in
                        Button { pick(place) } label: { PlaceRow(place: place) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: kind == .stops ? "Název zastávky" : "Zastávka, adresa, místo")
            .searchFocused($focused)
            .autocorrectionDisabled()
            .overlay(alignment: .top) {
                if isLoading { ProgressView().padding(.top, 8) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", systemImage: "xmark") { dismiss() }
                }
            }
            .task(id: trimmedQuery) {
                await fetch()
            }
            .onAppear { focused = true }
        }
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
        HStack(spacing: 12) {
            Image(systemName: place.symbol)
                .font(.body)
                .foregroundStyle(place.isCurrentLocation ? .blue : place.isStop ? .accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .foregroundStyle(.primary)
                if let subtitle = place.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(.rect)
    }
}
