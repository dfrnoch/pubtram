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
                    case .results: ResultsView()
                    case .connection(let id): ConnectionDetailView(connectionID: id)
                    }
                }
        }
    }
}

private struct RegularConnections: View {
    @Environment(SearchModel.self) private var model
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView(columnVisibility: $visibility) {
                HomeView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            } content: {
                Group {
                    if model.showsResults {
                        ResultsView()
                    } else {
                        ContentUnavailableView(
                            "Kam to bude?", systemImage: "tram.fill",
                            description: Text("Zadejte odkud a kam chcete jet, nebo vyberte oblíbenou trasu."))
                    }
                }
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
            } detail: {
                NavigationStack {
                    if let id = model.selectedID, model.connection(id: id) != nil {
                        ConnectionDetailView(connectionID: id)
                            .id(id)
                    } else {
                        ContentUnavailableView(
                            "Vyberte spojení", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("Detail s mapou a živými informacemi se zobrazí tady."))
                    }
                }
            }
            .onChange(of: model.showsResults) { _, showing in
                // Give results and detail the room on narrower iPads.
                if showing && proxy.size.width < 1200 { withAnimation { visibility = .doubleColumn } }
                if !showing { withAnimation { visibility = .all } }
            }
        }
    }
}
