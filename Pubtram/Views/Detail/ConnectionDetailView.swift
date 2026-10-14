import SwiftUI

struct ConnectionDetailView: View {
    let connectionID: Connection.ID
    @Environment(SearchModel.self) private var model

    var body: some View {
        if let connection = model.connection(id: connectionID) {
            GeometryReader { proxy in
                if proxy.size.width > 760 {
                    HStack(spacing: 0) {
                        ScrollView {
                            ConnectionTimeline(connection: connection, route: model.searchedRoute)
                                .padding()
                        }
                        .frame(width: min(460, proxy.size.width * 0.45))
                        RouteMapView(connection: connection)
                            .ignoresSafeArea(edges: [.bottom, .trailing])
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            RouteMapView(connection: connection)
                                .frame(height: max(240, proxy.size.height * 0.36))
                            ConnectionTimeline(connection: connection, route: model.searchedRoute)
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

    private func shareText(_ c: Connection) -> String {
        var lines: [String] = []
        if let route = model.searchedRoute {
            lines.append("\(route.from.name) → \(route.to.name)")
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

// MARK: - Timeline

struct ConnectionTimeline: View {
    let connection: Connection
    let route: SavedRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SummaryCard(connection: connection)
                .padding(.bottom, 20)

            if let route, connection.legs.first.map(isWalk) ?? false {
                EndpointRow(name: route.from.name, time: connection.departure, symbol: "circle.circle.fill", tint: .green)
            }

            ForEach(Array(connection.legs.enumerated()), id: \.element.id) { index, leg in
                switch leg {
                case .ride(let ride):
                    if let wait = waitBefore(index: index), wait >= 60 {
                        WaitRow(seconds: wait)
                    }
                    RideBlock(ride: ride)
                case .walk(let walk):
                    WalkRow(walk: walk)
                }
            }

            if let route, connection.legs.last.map(isWalk) ?? false {
                EndpointRow(name: route.to.name, time: connection.arrival, symbol: "mappin.circle.fill", tint: .red)
            }
        }
    }

    private func isWalk(_ leg: Leg) -> Bool {
        if case .walk = leg { true } else { false }
    }

    /// Idle time before boarding the ride at `index` (after the previous leg finished).
    private func waitBefore(index: Int) -> TimeInterval? {
        guard index > 0, case .ride(let ride) = connection.legs[index] else { return nil }
        let previousArrival = connection.legs[index - 1].arrival
        guard connection.legs[..<index].contains(where: { if case .ride = $0 { true } else { false } }) else {
            return nil
        }
        return ride.departure.timeIntervalSince(previousArrival)
    }
}

private struct SummaryCard: View {
    let connection: Connection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Fmt.time(connection.departure)) – \(Fmt.time(connection.arrival))")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("\(Fmt.day(connection.departure)) · \(Fmt.duration(connection.duration)) · \(Fmt.transfers(connection.transferCount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let ride = connection.firstRide {
                TimelineView(.everyMinute) { context in
                    let departure = ride.departure.addingTimeInterval(TimeInterval(max(0, ride.delay ?? 0)))
                    Label(
                        "Odjezd \(Fmt.countdown(to: departure, now: context.date))",
                        systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            ForEach(connection.prices, id: \.self) { price in
                if let url = price.url {
                    Link(destination: url) {
                        Label("Koupit jízdenku · \(price.formatted)", systemImage: "ticket.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Label("Jízdné \(price.formatted)\(price.seller.map { " · \($0)" } ?? "")", systemImage: "ticket")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum TimelineMetrics {
    static let timeWidth: CGFloat = 50
    static let railWidth: CGFloat = 16
}

private struct EndpointRow: View {
    let name: String
    let time: Date
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.time(time))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: TimelineMetrics.timeWidth, alignment: .trailing)
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: TimelineMetrics.railWidth)
            Text(name)
                .font(.headline)
            Spacer(minLength: 0)
        }
    }
}

private struct WalkRow: View {
    let walk: WalkLeg

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: TimelineMetrics.timeWidth)
            VerticalLine()
                .stroke(.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.5, 6]))
                .frame(width: TimelineMetrics.railWidth)
            Label {
                Text("Pěšky \(Fmt.distance(walk.distance)) · \(Fmt.duration(walk.arrival.timeIntervalSince(walk.departure)))")
            } icon: {
                Image(systemName: "figure.walk")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WaitRow: View {
    let seconds: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: TimelineMetrics.timeWidth)
            Color.clear.frame(width: TimelineMetrics.railWidth)
            Label("Přestup · čekání \(Fmt.duration(seconds))", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
    }
}

private struct RideBlock: View {
    let ride: RideLeg
    @State private var showsStops = false

    private var color: Color { ride.vehicle.color(line: ride.line) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing) {
                TimeLabel(planned: ride.departure, delay: ride.boardStop.flatMap(ride.delay(at:)))
                Spacer(minLength: 0)
                TimeLabel(planned: ride.arrival, delay: ride.alightStop.flatMap(ride.delay(at:)))
            }
            .frame(width: TimelineMetrics.timeWidth, alignment: .trailing)

            VStack(spacing: 0) {
                Circle().strokeBorder(color, lineWidth: 3).background(Circle().fill(.background))
                    .frame(width: 14, height: 14)
                Rectangle().fill(color).frame(width: 5).frame(maxHeight: .infinity)
                Circle().strokeBorder(color, lineWidth: 3).background(Circle().fill(.background))
                    .frame(width: 14, height: 14)
            }
            .frame(width: TimelineMetrics.railWidth)
            .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 10) {
                stopHeader(ride.boardStop, platform: ride.boardPlatform)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        LineBadge(vehicle: ride.vehicle, line: ride.line, size: .large)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("směr \(ride.direction)")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            if let agency = ride.agency {
                                Text(agency)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !ride.features.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(ride.features).sorted { $0.rawValue < $1.rawValue }, id: \.self) { f in
                                Image(systemName: f.symbol)
                                    .accessibilityLabel(f.label)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let text = ride.delayText, Fmt.delayMinutes(ride.delay ?? 0) > 0 {
                        Label(text, systemImage: "clock.badge.exclamationmark.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(ride.notices, id: \.self) { notice in
                        NoticeView(notice: notice)
                    }
                }

                if ride.intermediateStopCount > 0 {
                    Button {
                        withAnimation(.snappy) { showsStops.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showsStops ? 90 : 0))
                            Text("\(Fmt.stops(ride.intermediateStopCount)) · \(Fmt.duration(ride.arrival.timeIntervalSince(ride.departure)))")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showsStops {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(ride.riddenStops.dropFirst().dropLast()) { stop in
                                HStack(spacing: 8) {
                                    Text(Fmt.time(stop.time))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, alignment: .leading)
                                    Text(stop.name)
                                    if stop.onRequest {
                                        Image(systemName: "hand.raised.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Na znamení")
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .transition(.opacity)
                    }
                }

                stopHeader(ride.alightStop, platform: ride.alightPlatform)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    private func stopHeader(_ stop: StopTime?, platform: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(stop?.name ?? "?")
                .font(.headline)
            if let platform {
                PlatformBadge(platform: platform)
            }
        }
    }
}

private struct TimeLabel: View {
    let planned: Date
    let delay: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Fmt.time(planned))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let delay, Fmt.delayMinutes(delay) > 0 {
                Text(Fmt.time(planned.addingTimeInterval(TimeInterval(delay))))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Fmt.delayMinutes(delay) >= 5 ? .red : .orange)
            } else if delay != nil {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Jede včas")
            }
        }
    }
}

private struct NoticeView: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(notice.text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
            if let url = notice.url {
                Link("Více informací", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        .foregroundStyle(.primary)
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}
