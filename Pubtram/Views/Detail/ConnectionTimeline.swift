import SwiftUI

/// Vertical itinerary: rides with stops, walks, and transfer waits with risk warnings.
struct ConnectionTimeline: View {
    let connection: Connection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let origin = connection.origin, startsWithWalk {
                EndpointRow(name: origin.name, time: connection.departure, symbol: "circle.circle.fill", tint: .green)
            }

            ForEach(Array(connection.legs.enumerated()), id: \.element.id) { index, leg in
                switch leg {
                case .ride(let ride):
                    if let transfer = connection.transfer(before: ride.id), !hasWaitBefore(index) {
                        TransferRow(transfer: transfer, waitDuration: max(0, transfer.planned - transfer.walking))
                    }
                    RideBlock(ride: ride, journeyStart: connection.departure)
                case .walk(let walk):
                    WalkRow(walk: walk)
                case .wait(let wait):
                    if let next = nextRide(after: index), let transfer = connection.transfer(before: next.id) {
                        TransferRow(transfer: transfer, waitDuration: wait.arrival.timeIntervalSince(wait.departure))
                    } else {
                        TransferRow(transfer: nil, waitDuration: wait.arrival.timeIntervalSince(wait.departure))
                    }
                }
            }

            if let destination = connection.destination, endsWithWalk {
                EndpointRow(name: destination.name, time: connection.arrival, symbol: "mappin.circle.fill", tint: .red)
            }
        }
    }

    private var startsWithWalk: Bool {
        if case .walk = connection.legs.first { true } else { false }
    }

    private var endsWithWalk: Bool {
        if case .walk = connection.legs.last { true } else { false }
    }

    private func nextRide(after index: Int) -> RideLeg? {
        connection.legs[(index + 1)...].lazy.compactMap { if case .ride(let r) = $0 { r } else { nil } }.first
    }

    /// Whether an explicit wait leg already describes the transfer into the ride at `index`.
    private func hasWaitBefore(_ index: Int) -> Bool {
        var i = index - 1
        while i >= 0 {
            switch connection.legs[i] {
            case .wait: return true
            case .ride: return false
            case .walk: i -= 1
            }
        }
        return false
    }
}

private enum Metrics {
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
                .frame(width: Metrics.timeWidth, alignment: .trailing)
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: Metrics.railWidth)
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
            Color.clear.frame(width: Metrics.timeWidth)
            VerticalLine()
                .stroke(.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.5, 6]))
                .frame(width: Metrics.railWidth)
            Label {
                Text(walk.distance > 0
                    ? "Pěšky \(Fmt.distance(walk.distance)) · \(Fmt.duration(walk.arrival.timeIntervalSince(walk.departure)))"
                    : "Přesun · \(Fmt.duration(walk.arrival.timeIntervalSince(walk.departure)))")
            } icon: {
                Image(systemName: "figure.walk")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TransferRow: View {
    let transfer: Transfer?
    let waitDuration: TimeInterval

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear.frame(width: Metrics.timeWidth)
            Color.clear.frame(width: Metrics.railWidth)
            VStack(alignment: .leading, spacing: 4) {
                Label(waitText, systemImage: "hourglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let transfer {
                    switch transfer.risk {
                    case .missed:
                        Label(
                            "Kvůli zpoždění přestup pravděpodobně nestihnete",
                            systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    case .tight:
                        Label(
                            "Těsný přestup – rezerva \(max(0, Int(transfer.margin / 60))) min",
                            systemImage: "timer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    case .ok:
                        EmptyView()
                    }
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
    }

    private var waitText: String {
        waitDuration >= 60 ? "Přestup · čekání \(Fmt.duration(waitDuration))" : "Přestup"
    }
}

private struct RideBlock: View {
    let ride: RideLeg
    let journeyStart: Date
    @State private var showsStops = false

    private var color: Color { ride.vehicle.color(line: ride.line) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing) {
                StopTimeLabel(planned: ride.departure, delay: ride.boardStop.flatMap(ride.delay(at:)), journeyStart: journeyStart)
                Spacer(minLength: 0)
                StopTimeLabel(planned: ride.arrival, delay: ride.alightStop.flatMap(ride.delay(at:)), journeyStart: journeyStart)
            }
            .frame(width: Metrics.timeWidth, alignment: .trailing)

            VStack(spacing: 0) {
                Circle().strokeBorder(color, lineWidth: 3).background(Circle().fill(.background))
                    .frame(width: 14, height: 14)
                Rectangle().fill(color).frame(width: 5).frame(maxHeight: .infinity)
                Circle().strokeBorder(color, lineWidth: 3).background(Circle().fill(.background))
                    .frame(width: 14, height: 14)
            }
            .frame(width: Metrics.railWidth)
            .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 10) {
                stopHeader(ride.boardStop, platform: ride.boardPlatform)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        LineBadge(vehicle: ride.vehicle, line: ride.line, size: .large)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("směr \(ride.direction)")
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
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
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    if showsStops {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(ride.riddenStops.dropFirst().dropLast()) { stop in
                                IntermediateStopRow(stop: stop, ride: ride)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(stop?.name ?? "?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let platform {
                PlatformBadge(platform: platform)
            }
        }
    }
}

private struct IntermediateStopRow: View {
    let stop: StopTime
    let ride: RideLeg

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.time(stop.time))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(stop.name)
                .fixedSize(horizontal: false, vertical: true)
            if stop.onRequest {
                Image(systemName: "hand.raised.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Na znamení")
            }
            Spacer(minLength: 4)
            if let delay = ride.stopDelays[stop.stopID] ?? stop.parentID.flatMap({ ride.stopDelays[$0] }),
                Fmt.delayMinutes(delay) > 0
            {
                Text("+\(Fmt.delayMinutes(delay))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DelayBadge.color(Fmt.delayMinutes(delay)))
            }
        }
        .font(.caption)
    }
}

private struct StopTimeLabel: View {
    let planned: Date
    let delay: Int?
    let journeyStart: Date

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
            if let offset = Fmt.dayOffset(from: journeyStart, to: planned) {
                Text(offset == 1 ? "zítra" : "+\(offset) d")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
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
                .fixedSize(horizontal: false, vertical: true)
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
