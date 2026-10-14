import SwiftUI

/// Home (search + favorites) → results → connection detail.
/// A navigation stack on iPhone, a three-column split view on iPad.
struct ConnectionsTab: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            CompactConnections()
        } else {
            RegularConnections()
        }
    }
}

enum SearchDestination: Hashable {
    case results
    case connection(Connection.ID)
}

private struct CompactConnections: View {
    @Environment(SearchModel.self) private var model

    /// The path is derived from the model so deep links and size-class changes stay consistent.
    private var path: Binding<[SearchDestination]> {
        Binding {
            var path: [SearchDestination] = []
            if model.showsResults {
                path.append(.results)
                if let id = model.selectedID { path.append(.connection(id)) }
            }
            return path
        } set: { newPath in
            model.showsResults = newPath.contains(.results)
            model.selectedID = newPath.compactMap { if case .connection(let id) = $0 { id } else { nil } }.last
        }
    }

    var body: some View {
        NavigationStack(path: path) {
            HomeView()
                .navigationDestination(for: SearchDestination.self) { destination in
                    switch destination {
                    case .results: ResultsView(pushesDetail: true)
                    case .connection(let id): ConnectionDetailView(connectionID: id)
                    }
                }
        }
    }
}

/// iPad: the sidebar is a stack (home → results) like Apple Maps; the detail sits beside it.
private struct RegularConnections: View {
    @Environment(SearchModel.self) private var model
    @State private var visibility = NavigationSplitViewVisibility.all

    private var sidebarPath: Binding<[SearchDestination]> {
        Binding {
            model.showsResults ? [.results] : []
        } set: { newPath in
            model.showsResults = newPath.contains(.results)
            if !model.showsResults { model.selectedID = nil }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            NavigationStack(path: sidebarPath) {
                HomeView()
                    .navigationDestination(for: SearchDestination.self) { _ in
                        ResultsView(pushesDetail: false)
                    }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 420, max: 500)
        } detail: {
            NavigationStack {
                if let id = model.selectedID, model.connection(id: id) != nil {
                    ConnectionDetailView(connectionID: id)
                        .id(id)
                } else if model.showsResults {
                    ContentUnavailableView(
                        "Vyberte spojení", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Detail s mapou a živými informacemi se zobrazí tady."))
                } else {
                    ContentUnavailableView(
                        "Kam to bude?", systemImage: "tram.fill",
                        description: Text("Zadejte odkud a kam chcete jet, nebo vyberte oblíbenou trasu."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.showsResults) { _, showing in
            if showing { visibility = .all }
        }
        .onChange(of: model.connections.first?.id) { _, first in
            // Pick the first result so the detail column isn't empty.
            if model.selectedID == nil, let first { model.selectedID = first }
        }
    }
}
