import CoreLocation

enum LocationError: LocalizedError {
    case denied, unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Přístup k poloze není povolen. Povolte ho v Nastavení."
        case .unavailable: "Polohu se nepodařilo zjistit."
        }
    }
}

@MainActor
enum LocationProvider {
    private static var cached: (CLLocationCoordinate2D, Date)?

    /// One-shot current location (cached for a minute).
    static func current() async throws -> CLLocationCoordinate2D {
        if let (coordinate, date) = cached, date.timeIntervalSinceNow > -60 { return coordinate }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw LocationError.denied }
            if let location = update.location, location.horizontalAccuracy < 500 {
                cached = (location.coordinate, .now)
                // Widgets can't ask for location themselves; they reuse the last known one.
                SharedStore.lastLocation = Coordinate(location.coordinate)
                return location.coordinate
            }
        }
        throw LocationError.unavailable
    }
}
