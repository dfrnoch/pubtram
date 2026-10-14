import AppIntents
import SwiftUI
import WidgetKit

struct RouteEntry: TimelineEntry {
    let date: Date
    let route: SavedRoute?
    let connections: [Connection]
    var message: String?

    var upcoming: [Connection] { connections.filter { $0.effectiveDeparture > date.addingTimeInterval(-30) } }
}

struct RouteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: .now, route: nil, connections: [], message: nil)
    }

    func snapshot(for configuration: SelectRouteIntent, in context: Context) async -> RouteEntry {
        await entries(for: configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectRouteIntent, in context: Context) async -> Timeline<RouteEntry> {
        let entries = await entries(for: configuration)
        let failed = entries.first?.message != nil
        // Refresh sooner when the next connection leaves soon.
        let next = entries.first?.upcoming.first?.effectiveDeparture ?? .now.addingTimeInterval(15 * 60)
        let refresh = failed ? Date.now.addingTimeInterval(300) : min(next.addingTimeInterval(60), .now.addingTimeInterval(15 * 60))
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entries(for configuration: SelectRouteIntent) async -> [RouteEntry] {
        guard let route = configuration.route?.route ?? SharedStore.favoriteRoutes.first else {
            return [RouteEntry(date: .now, route: nil, connections: [], message: "Přidejte si oblíbenou trasu v aplikaci.")]
        }
        do {
            let connections = try await PubtranClient.shared.upcomingConnections(for: route, count: 4)
            return Date.minuteSteps(count: 16).map { RouteEntry(date: $0, route: route, connections: connections) }
        } catch {
            return [RouteEntry(date: .now, route: route, connections: [], message: "Spojení se nepodařilo načíst.")]
        }
    }
}

struct RouteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Route", intent: SelectRouteIntent.self, provider: RouteProvider()) { entry in
            RouteWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.route.map { DeepLink.route(id: $0.id).url } ?? DeepLink.search.url)
        }
        .configurationDisplayName("Oblíbená trasa")
        .description("Nejbližší spojení na vaší trase.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RouteWidgetView: View {
    let entry: RouteEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let c = entry.upcoming.first {
                Text("\(Fmt.time(c.departure)) \(lines(c)) · \(Fmt.countdown(to: c.effectiveDeparture, now: entry.date))")
            } else {
                Text(entry.route?.title ?? "Pubtram")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.route?.title ?? "Trasa")
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                if let c = entry.upcoming.first {
                    Text("\(Fmt.time(c.departure)) → \(Fmt.time(c.arrival))")
                        .font(.caption.weight(.semibold))
                    Text("\(lines(c)) · \(Fmt.countdown(to: c.effectiveDeparture, now: entry.date))")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private func lines(_ c: Connection) -> String {
        c.rides.map(\.displayLine).joined(separator: "›")
    }

    @ViewBuilder
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: entry.route?.title ?? "Trasa", symbol: "star.fill")
            if let message = entry.message {
                WidgetMessage(text: message, symbol: "tram")
            } else if let c = entry.upcoming.first {
                Spacer(minLength: 0)
                Text(Fmt.countdown(to: c.effectiveDeparture, now: entry.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(Fmt.time(c.departure))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                LegStrip(legs: c.legs, size: .small)
                Text("v cíli \(Fmt.time(c.arrival))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                WidgetMessage(text: "Žádné spojení", symbol: "tram")
            }
        }
    }

    @ViewBuilder
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: entry.route?.title ?? "Trasa", symbol: "star.fill")
            if let message = entry.message {
                WidgetMessage(text: message, symbol: "tram")
            } else {
                ForEach(entry.upcoming.prefix(3)) { c in
                    HStack(spacing: 8) {
                        Text("\(Fmt.time(c.departure))–\(Fmt.time(c.arrival))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 78, alignment: .leading)
                        JourneyBar(legs: c.legs, height: 16)
                        Text(Fmt.shortCountdown(to: c.effectiveDeparture, now: entry.date))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
