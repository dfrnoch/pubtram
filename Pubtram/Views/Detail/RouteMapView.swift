import MapKit
import SwiftUI

struct RouteMapView: View {
    let connection: Connection
    /// Header maps are static previews; tapping them opens the full map.
    var interactive = true
    @State private var geometries: [String: [CLLocationCoordinate2D]] = [:]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(connection.legs) { leg in
                let coords = coordinates(for: leg)
                if coords.count > 1 {
                    switch leg {
                    case .ride(let ride):
                        MapPolyline(coordinates: coords)
                            .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coords)
                            .stroke(
                                ride.vehicle.color(line: ride.line),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    case .walk, .wait:
                        MapPolyline(coordinates: coords)
                            .stroke(.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
                    }
                }
            }

            ForEach(connection.rides) { ride in
                if let stop = ride.boardStop, let c = stop.coordinate {
                    Annotation(stop.name, coordinate: c.cl, anchor: .center) {
                        stopDot(ride.vehicle.color(line: ride.line))
                    }
                    .annotationTitles(.hidden)
                }
                if let stop = ride.alightStop, let c = stop.coordinate {
                    Annotation(stop.name, coordinate: c.cl, anchor: .center) {
                        stopDot(ride.vehicle.color(line: ride.line))
                    }
                    .annotationTitles(.hidden)
                }
                if let position = ride.vehiclePosition {
                    Annotation("\(ride.vehicle.name) \(ride.line)", coordinate: position.cl) {
                        LineBadge(vehicle: ride.vehicle, line: ride.line, size: .small)
                            .shadow(radius: 2)
                    }
                    .annotationTitles(.hidden)
                }
            }

            if let start = connection.startCoordinate {
                Marker("Start", systemImage: "figure.walk.departure", coordinate: start.cl)
                    .tint(.green)
            }
            if let end = connection.endCoordinate {
                Marker("Cíl", systemImage: "flag.checkered", coordinate: end.cl)
                    .tint(.red)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if interactive {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
        }
        .allowsHitTesting(interactive)
        .task(id: connection.id) {
            await loadGeometries()
        }
    }

    private func stopDot(_ color: Color) -> some View {
        Circle()
            .fill(.white)
            .stroke(color, lineWidth: 3)
            .frame(width: 12, height: 12)
    }

    /// Detailed shape when loaded, otherwise straight lines between stops.
    private func coordinates(for leg: Leg) -> [CLLocationCoordinate2D] {
        if let g = geometries[leg.id], g.count > 1 { return g }
        switch leg {
        case .ride(let ride):
            return ride.riddenStops.compactMap { $0.coordinate?.cl }
        case .walk(let walk):
            return [walk.from, walk.to].compactMap { $0?.cl }
        case .wait:
            return []
        }
    }

    private func loadGeometries() async {
        let client = PubtranClient.shared
        await withTaskGroup(of: (String, [CLLocationCoordinate2D]).self) { group in
            for leg in connection.legs where geometries[leg.id] == nil {
                group.addTask {
                    switch leg {
                    case .ride(let ride):
                        return (leg.id, (try? await client.rideGeometry(ride)) ?? [])
                    case .walk(let walk):
                        guard let from = walk.from, let to = walk.to, walk.distance > 30 else { return (leg.id, []) }
                        return (leg.id, (try? await client.walkGeometry(from: from, to: to)) ?? [])
                    case .wait:
                        return (leg.id, [])
                    }
                }
            }
            for await (id, coords) in group where !coords.isEmpty {
                geometries[id] = coords
            }
        }
    }
}
