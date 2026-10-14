import AppIntents
import CoreSpotlight
import UIKit
import WidgetKit

/// Keeps widgets, home-screen quick actions, Siri phrases and Spotlight in sync with favorites.
@MainActor
enum SystemIntegration {
    static func favoritesChanged(routes: [SavedRoute], boards: [SavedBoard]) {
        WidgetCenter.shared.reloadAllTimelines()
        updateQuickActions(routes: routes, boards: boards)
        PubtramShortcuts.updateAppShortcutParameters()
        Task { await indexSpotlight(routes: routes, boards: boards) }
    }

    /// Long-press actions on the app icon: top favorite routes and boards.
    static func updateQuickActions(routes: [SavedRoute], boards: [SavedBoard]) {
        var items = routes.prefix(3).map { route in
            UIApplicationShortcutItem(
                type: "route", localizedTitle: route.title,
                localizedSubtitle: route.name == nil ? nil : route.placesLabel,
                icon: UIApplicationShortcutIcon(systemImageName: "star.fill"),
                userInfo: ["url": DeepLink.route(id: route.id).url.absoluteString as NSString])
        }
        if let board = boards.first {
            items.append(
                UIApplicationShortcutItem(
                    type: "board", localizedTitle: "Odjezdy: \(board.title)", localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: "clock.fill"),
                    userInfo: ["url": DeepLink.board(id: board.id).url.absoluteString as NSString]))
        }
        UIApplication.shared.shortcutItems = items
    }

    static func indexSpotlight(routes: [SavedRoute], boards: [SavedBoard]) async {
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: RouteEntity.self)
        try? await index.deleteAppEntities(ofType: BoardEntity.self)
        try? await index.indexAppEntities(routes.map(RouteEntity.init))
        try? await index.indexAppEntities(boards.map(BoardEntity.init))
    }
}

extension RouteEntity: IndexedEntity {}
extension BoardEntity: IndexedEntity {}

// MARK: - App & scene delegates (quick actions)

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem { handle(item) }
    }

    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        handle(shortcutItem)
        completionHandler(true)
    }

    private func handle(_ item: UIApplicationShortcutItem) {
        guard let string = item.userInfo?["url"] as? String, let url = URL(string: string) else { return }
        Task { @MainActor in AppRouter.shared.handle(url: url) }
    }
}
