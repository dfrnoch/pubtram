import AppIntents
import Foundation

/// A favorite route, exposed to Shortcuts, Siri, widgets and Spotlight.
struct RouteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trasa")
    static let defaultQuery = RouteQuery()

    let id: String
    let title: String
    let subtitle: String?

    init(_ route: SavedRoute) {
        id = route.id
        title = route.title
        subtitle = route.name == nil ? nil : route.placesLabel
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { "\($0)" },
            image: .init(systemName: "star.fill"))
    }

    var route: SavedRoute? { SharedStore.favoriteRoutes.first { $0.id == id } }
}

struct RouteQuery: EntityQuery {
    func entities(for identifiers: [RouteEntity.ID]) async throws -> [RouteEntity] {
        SharedStore.favoriteRoutes.filter { identifiers.contains($0.id) }.map(RouteEntity.init)
    }

    func suggestedEntities() async throws -> [RouteEntity] {
        SharedStore.favoriteRoutes.map(RouteEntity.init)
    }
}

/// A saved departure board (one or more stops).
struct BoardEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Zastávka")
    static let defaultQuery = BoardQuery()

    let id: String
    let title: String
    let subtitle: String?

    init(_ board: SavedBoard) {
        id = board.id
        title = board.title
        subtitle = board.subtitle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { "\($0)" },
            image: .init(systemName: "signpost.right.fill"))
    }

    var board: SavedBoard? { SharedStore.boards.first { $0.id == id } }
}

struct BoardQuery: EntityQuery {
    func entities(for identifiers: [BoardEntity.ID]) async throws -> [BoardEntity] {
        SharedStore.boards.filter { identifiers.contains($0.id) }.map(BoardEntity.init)
    }

    func suggestedEntities() async throws -> [BoardEntity] {
        SharedStore.boards.map(BoardEntity.init)
    }
}

// MARK: - Widget configuration

struct SelectBoardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Odjezdy ze zastávky"
    static let description = IntentDescription("Zobrazí nejbližší odjezdy z uložené zastávky.")

    @Parameter(title: "Zastávka")
    var board: BoardEntity?

    init() {}
}

struct SelectRouteIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Nejbližší spojení"
    static let description = IntentDescription("Zobrazí nejbližší spojení na oblíbené trase.")

    @Parameter(title: "Trasa")
    var route: RouteEntity?

    init() {}
}
