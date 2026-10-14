import SwiftUI

struct ConnectionRow: View {
    let connection: Connection
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Fmt.time(connection.departure)) – \(Fmt.time(connection.arrival))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if let delay = connection.maxDelay {
                    DelayBadge(delay: delay, compact: true)
                }
                if connection.hasWarnings {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Omezení provozu")
                }
                Spacer(minLength: 4)
                Text(Fmt.duration(connection.duration))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LegStrip(legs: connection.legs)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let ride = connection.firstRide {
                    TimelineView(.everyMinute) { context in
                        Text(Fmt.countdown(to: ride.departure.addingTimeInterval(TimeInterval(max(0, ride.delay ?? 0))), now: context.date))
                            .font(.footnote.weight(.semibold))
                            // The selection highlight uses the accent color, so the tint would vanish.
                            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                    }
                    Text("z \(ride.boardStop?.name ?? "")")
                        .lineLimit(1)
                    if let platform = ride.boardPlatform {
                        PlatformBadge(platform: platform)
                    }
                }
                Spacer(minLength: 4)
                Text(trailingInfo)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var trailingInfo: String {
        var parts = [Fmt.transfers(connection.transferCount)]
        if let price = connection.prices.first { parts.append(price.formatted) }
        let day = Fmt.day(connection.departure)
        if day != "dnes" { parts.insert(day, at: 0) }
        return parts.joined(separator: " · ")
    }
}
