import AppIntents
import SwiftUI
import WidgetKit

struct DeparturesEntry: TimelineEntry {
    let date: Date
    let board: SavedBoard?
    let departures: [Departure]
    var message: String?

    var upcoming: [Departure] { departures.filter { $0.time > date.addingTimeInterval(-30) } }
}

struct DeparturesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry { .sample }

    func snapshot(for configuration: SelectBoardIntent, in context: Context) async -> DeparturesEntry {
        if context.isPreview && SharedStore.boards.isEmpty { return .sample }
        return await entries(for: configuration).first ?? .sample
    }

    func timeline(for configuration: SelectBoardIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let entries = await entries(for: configuration)
        let failed = entries.first?.message != nil
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(failed ? 300 : 15 * 60)))
    }

    private func entries(for configuration: SelectBoardIntent) async -> [DeparturesEntry] {
        guard let board = configuration.board?.board ?? SharedStore.boards.first else {
            return [DeparturesEntry(date: .now, board: nil, departures: [], message: "Uložte si zastávku v aplikaci.")]
        }
        do {
            let departures = try await PubtranClient.shared.departures(for: board)
            return Date.minuteSteps(count: 20).map { DeparturesEntry(date: $0, board: board, departures: departures) }
        } catch {
            return [DeparturesEntry(date: .now, board: board, departures: [], message: "Odjezdy se nepodařilo načíst.")]
        }
    }
}

struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Departures", intent: SelectBoardIntent.self, provider: DeparturesProvider()) { entry in
            DeparturesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.board.map { DeepLink.board(id: $0.id).url } ?? DeepLink.departures.url)
        }
        .configurationDisplayName("Odjezdy")
        .description("Nejbližší odjezdy z vaší zastávky.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct DeparturesWidgetView: View {
    let entry: DeparturesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let d = entry.upcoming.first {
                Text("\(d.displayLine) \(d.destination) \(Fmt.countdown(to: d.time, now: entry.date))")
            } else {
                Text(entry.board?.title ?? "Pubtram")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.board?.title ?? "Odjezdy")
                    .font(.headline)
                    .widgetAccentable()
                ForEach(entry.upcoming.prefix(2)) { d in
                    HStack(spacing: 4) {
                        Text(d.displayLine).fontWeight(.bold)
                        Text(d.destination).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Fmt.shortCountdown(to: d.time, now: entry.date)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        default:
            content
        }
    }

    private var rowCount: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 9
        default: 4
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 7) {
            WidgetHeader(title: entry.board?.title ?? "Odjezdy", symbol: "signpost.right.fill")
            if let message = entry.message {
                WidgetMessage(text: message, symbol: "clock.badge.questionmark")
            } else if entry.upcoming.isEmpty {
                WidgetMessage(text: "V nejbližší době nic nejede.", symbol: "moon.zzz")
            } else {
                ForEach(entry.upcoming.prefix(rowCount)) { d in
                    HStack(spacing: 6) {
                        LineBadge(vehicle: d.vehicle, line: d.line, size: .small, showsIcon: family != .systemSmall)
                        if family != .systemSmall {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(d.destination).font(.caption.weight(.medium)).lineLimit(1)
                                if family == .systemLarge, let stop = d.stopName {
                                    Text(stop).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        } else {
                            Text(d.destination).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Text(Fmt.shortCountdown(to: d.time, now: entry.date))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(d.time.timeIntervalSince(entry.date) < 300 ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

extension DeparturesEntry {
    static var sample: DeparturesEntry {
        let now = Date.now
        let departures = [
            ("9", VehicleType.tram, "Sídliště Řepy", 2), ("B", .metro, "Zličín", 3), ("12", .tram, "Lehovec", 5),
            ("20", .tram, "Divoká Šárka", 7), ("B", .metro, "Černý Most", 8), ("137", .bus, "Na Knížecí", 11),
        ].map { Departure(time: now.addingTimeInterval(Double($0.3) * 60), line: $0.0, vehicle: $0.1, destination: $0.2) }
        return DeparturesEntry(date: now, board: SavedBoard(stops: [], name: "Anděl"), departures: departures)
    }
}

#Preview(as: .systemMedium) {
    DeparturesWidget()
} timeline: {
    DeparturesEntry.sample
}
