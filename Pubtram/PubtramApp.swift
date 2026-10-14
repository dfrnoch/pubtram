import SwiftUI

@main
struct PubtramApp: App {
    @State private var store: AppStore
    @State private var search: SearchModel
    @State private var departures = DeparturesModel()

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        _search = State(initialValue: SearchModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(search)
                .environment(departures)
        }
    }
}

enum AppTab: Hashable {
    case connections, departures
}

struct RootView: View {
    @State private var tab: AppTab = .connections

    var body: some View {
        TabView(selection: $tab) {
            Tab("Spojení", systemImage: "arrow.triangle.turn.up.right.diamond.fill", value: .connections) {
                ConnectionsScreen()
            }
            Tab("Odjezdy", systemImage: "clock.fill", value: .departures) {
                DeparturesScreen()
            }
        }
    }
}
