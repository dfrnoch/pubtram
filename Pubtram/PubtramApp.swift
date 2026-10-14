import SwiftUI

@main
struct PubtramApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(router.store)
                .environment(router.search)
                .environment(router.boards)
                .environment(LiveActivityController.shared)
                .onOpenURL { router.handle(url: $0) }
                .task {
                    SystemIntegration.updateQuickActions(routes: router.store.favoriteRoutes, boards: router.store.boards)
                }
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Spojení", systemImage: "arrow.triangle.turn.up.right.diamond.fill", value: .connections) {
                ConnectionsTab()
            }
            Tab("Odjezdy", systemImage: "clock.fill", value: .departures) {
                DeparturesTab()
            }
        }
    }
}
