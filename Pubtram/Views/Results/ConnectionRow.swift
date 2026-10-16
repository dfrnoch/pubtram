import SwiftUI

struct ConnectionRow: View {
    let connection: Connection
    var isSelected = false
    var isFastest = false
    var showsDestination = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                times
                if let delay = connection.maxDelay {
                    DelayBadge(delay: delay, compact: true)
                }
                Spacer(minLength: 4)
                Text(Fmt.duration(connection.duration))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            JourneyBar(legs: connection.legs)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let ride = connection.firstRide {
                    TimelineView(.everyMinute) { context in
                        Text(Fmt.departureHint(to: connection.effectiveDeparture, now: context.date))
                            .font(.footnote.weight(.semibold))
                            // The selection highlight uses the accent color, so the tint would vanish.
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                    }
                    Text(ride.boardStop?.name ?? "")
                        .lineLimit(1)
                    if let platform = ride.boardPlatform {
                        PlatformBadge(platform: platform)
                    }
                }
                Spacer(minLength: 4)
                Text(Fmt.transfers(connection.transferCount))
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.text) { tag in
                        Pill(text: tag.text, symbol: tag.symbol, color: tag.color)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var times: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Fmt.time(connection.departure))
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(Fmt.time(connection.arrival))
            if let offset = Fmt.dayOffset(from: connection.departure, to: connection.arrival) {
                Text("+\(offset)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .baselineOffset(8)
            }
        }
        .font(.title3.weight(.semibold))
        .monospacedDigit()
    }

    private struct Tag {
        let text: String
        let symbol: String
        let color: Color
    }

    private var tags: [Tag] {
        var tags: [Tag] = []
        if isFastest { tags.append(Tag(text: "Nejrychlejší", symbol: "hare.fill", color: .green)) }
        let risks = connection.rides.dropFirst().compactMap { connection.transfer(before: $0.id)?.risk }
        if risks.contains(.missed) {
            tags.append(Tag(text: "Přestup ohrožen", symbol: "exclamationmark.triangle.fill", color: .red))
        } else if risks.contains(.tight) {
            tags.append(Tag(text: "Těsný přestup", symbol: "timer", color: .orange))
        }
        if connection.hasWarnings {
            tags.append(Tag(text: "Omezení", symbol: "exclamationmark.triangle.fill", color: .orange))
        }
        if showsDestination, let destination = connection.destination {
            tags.append(Tag(text: destination.name, symbol: "mappin", color: .secondary))
        }
        return tags
    }
}
