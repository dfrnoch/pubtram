import SwiftUI

struct ConnectionDetailView: View {
    let connectionID: Connection.ID
    @Environment(SearchModel.self) private var model
    @Environment(LiveActivityController.self) private var liveActivities
    @State private var showsFullMap = false

    var body: some View {
        if let connection = model.connection(id: connectionID) {
            GeometryReader { proxy in
                if proxy.size.width > 760 {
                    HStack(spacing: 0) {
                        ScrollView {
                            content(connection)
                                .padding()
                        }
                        .frame(width: min(480, proxy.size.width * 0.46))
                        RouteMapView(connection: connection)
                            .ignoresSafeArea(edges: [.bottom, .trailing])
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            mapHeader(connection)
                                .frame(height: max(220, proxy.size.height * 0.32))
                            content(connection)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("\(Fmt.time(connection.departure)) – \(Fmt.time(connection.arrival))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText(connection)) {
                        Label("Sdílet", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .fullScreenCover(isPresented: $showsFullMap) {
                NavigationStack {
                    RouteMapView(connection: connection)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Mapa trasy")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Hotovo", systemImage: "checkmark") { showsFullMap = false }
                            }
                        }
                }
            }
            .task(id: connectionID) {
                // Keep live delays fresh while the detail is open.
                while !Task.isCancelled {
                    await model.refreshLive(only: [connectionID])
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        } else {
            ContentUnavailableView("Spojení už není k dispozici", systemImage: "tram")
        }
    }

    private func mapHeader(_ connection: Connection) -> some View {
        RouteMapView(connection: connection, interactive: false)
            .overlay(alignment: .bottomTrailing) {
                Label("Zvětšit mapu", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(12)
            }
            .contentShape(.rect)
            .onTapGesture { showsFullMap = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Zobrazit mapu trasy")
    }

    private func content(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SummaryCard(connection: connection)
            ActionsRow(connection: connection, title: model.searchedRoute?.placesLabel ?? "Cesta")
            ConnectionTimeline(connection: connection)
            if !connection.ticketOffers.isEmpty || connection.totalPrice != nil {
                TicketsSection(connection: connection)
            }
        }
    }

    private func shareText(_ c: Connection) -> String {
        var lines: [String] = []
        if let route = model.searchedRoute {
            lines.append("\(route.placesLabel)")
        }
        lines.append("\(Fmt.day(c.departure)) \(Fmt.time(c.departure)) – \(Fmt.time(c.arrival)) (\(Fmt.duration(c.duration)))")
        for ride in c.rides {
            var line = "\(Fmt.time(ride.departure)) \(ride.vehicle.name) \(ride.line) z \(ride.boardStop?.name ?? "")"
            if let p = ride.boardPlatform { line += " (\(Platform.label(p)))" }
            line += " → \(ride.alightStop?.name ?? "") \(Fmt.time(ride.arrival))"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Summary & actions

private struct SummaryCard: View {
    let connection: Connection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Fmt.time(connection.departure)) – \(Fmt.time(connection.arrival))")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                if let offset = Fmt.dayOffset(from: connection.departure, to: connection.arrival) {
                    Text("+\(offset)")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            JourneyBar(legs: connection.legs, height: 26)
            if connection.firstRide != nil {
                TimelineView(.everyMinute) { context in
                    Label(
                        "Vyrazte \(Fmt.departureHint(to: connection.effectiveDeparture, now: context.date))",
                        systemImage: "figure.walk.departure")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var summaryLine: String {
        var parts = [Fmt.day(connection.departure), Fmt.duration(connection.duration), Fmt.transfers(connection.transferCount)]
        if let price = connection.totalPrice { parts.append(price.formatted) }
        return parts.joined(separator: " · ")
    }
}

private struct ActionsRow: View {
    let connection: Connection
    let title: String
    @Environment(LiveActivityController.self) private var liveActivities

    var body: some View {
        let tracking = liveActivities.isTracking(connection.id)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if tracking {
                    liveActivities.stop(connection.id)
                } else {
                    liveActivities.start(connection, title: title)
                }
            } label: {
                Label(
                    tracking ? "Ukončit sledování" : "Sledovat cestu",
                    systemImage: tracking ? "stop.circle.fill" : "livephoto")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(connection.arrival < .now)
            if let error = liveActivities.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct TicketsSection: View {
    let connection: Connection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jízdenky")
                .font(.headline)
            if let total = connection.totalPrice, total.kind == .total {
                Text("Celková cena cca \(total.formatted)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(connection.ticketOffers, id: \.self) { offer in
                if let url = offer.url {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Image(systemName: "ticket.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(offer.seller ?? "Koupit jízdenku")
                                    .font(.subheadline.weight(.semibold))
                                if let from = offer.from, let to = offer.to, offer.kind == .partial {
                                    Text("\(from) → \(to)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(offer.formatted)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
