import AppIntents
import SwiftUI

/// "Co mi jede z Anděla?" – speaks and shows the next departures.
struct NextDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Nejbližší odjezdy"
    static let description = IntentDescription("Zjistí nejbližší odjezdy z uložené zastávky.")

    @Parameter(title: "Zastávka")
    var board: BoardEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Odjezdy z \(\.$board)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let saved = board.board else {
            throw IntentError.message("Zastávka už není uložená.")
        }
        let departures = Array(try await PubtranClient.shared.departures(for: saved).filter { $0.time > .now }.prefix(5))
        guard let first = departures.first else {
            return .result(dialog: "Z \(saved.title) teď nic nejede.", view: DeparturesSnippet(title: saved.title, departures: []))
        }
        let dialog = "\(first.vehicle.name) \(first.displayLine) směr \(first.destination) jede \(Fmt.countdown(to: first.time))."
        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: DeparturesSnippet(title: saved.title, departures: departures))
    }
}

/// "Kdy mi to jede domů?" – finds the next connection on a favorite route.
struct NextConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Nejbližší spojení"
    static let description = IntentDescription("Najde nejbližší spojení na oblíbené trase.")

    @Parameter(title: "Trasa")
    var route: RouteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Nejbližší spojení \(\.$route)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let saved = route.route else {
            throw IntentError.message("Trasa už není mezi oblíbenými.")
        }
        let connections = try await PubtranClient.shared.upcomingConnections(for: saved, count: 3)
        guard let first = connections.first else {
            return .result(dialog: "Žádné spojení jsem nenašel.", view: ConnectionsSnippet(title: saved.title, connections: []))
        }
        let lines = first.rides.map { "\($0.vehicle.name) \($0.displayLine)" }.joined(separator: ", ")
        let dialog = "Odjezd \(Fmt.countdown(to: first.effectiveDeparture)) v \(Fmt.time(first.departure)), \(lines). V cíli v \(Fmt.time(first.arrival))."
        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: ConnectionsSnippet(title: saved.title, connections: connections))
    }
}

/// Opens the app with results for a favorite route (also used by Spotlight).
struct OpenRouteIntent: OpenIntent {
    static let title: LocalizedStringResource = "Otevřít trasu"

    @Parameter(title: "Trasa")
    var target: RouteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.handle(.route(id: target.id))
        return .result()
    }
}

/// Opens a saved departure board.
struct OpenBoardIntent: OpenIntent {
    static let title: LocalizedStringResource = "Otevřít odjezdy"

    @Parameter(title: "Zastávka")
    var target: BoardEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.handle(.board(id: target.id))
        return .result()
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .message(let text): "\(text)"
        }
    }
}

struct PubtramShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextConnectionIntent(),
            phrases: [
                "Kdy mi to jede v \(.applicationName)",
                "Nejbližší spojení v \(.applicationName)",
                "Spojení \(\.$route) v \(.applicationName)",
            ],
            shortTitle: "Nejbližší spojení",
            systemImageName: "tram.fill")
        AppShortcut(
            intent: NextDeparturesIntent(),
            phrases: [
                "Odjezdy v \(.applicationName)",
                "Co mi jede v \(.applicationName)",
                "Odjezdy z \(\.$board) v \(.applicationName)",
            ],
            shortTitle: "Odjezdy",
            systemImageName: "clock.fill")
    }

    static let shortcutTileColor: ShortcutTileColor = .red
}

// MARK: - Snippets

struct DeparturesSnippet: View {
    let title: String
    let departures: [Departure]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(departures) { d in
                HStack {
                    LineBadge(vehicle: d.vehicle, line: d.line, size: .small)
                    Text(d.destination).lineLimit(1)
                    Spacer()
                    Text(Fmt.countdown(to: d.time)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding()
    }
}

struct ConnectionsSnippet: View {
    let title: String
    let connections: [Connection]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(connections) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Fmt.time(c.departure)) – \(Fmt.time(c.arrival))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Text(Fmt.countdown(to: c.effectiveDeparture)).font(.caption).foregroundStyle(.secondary)
                    }
                    JourneyBar(legs: c.legs, height: 18)
                }
            }
        }
        .padding()
    }
}
