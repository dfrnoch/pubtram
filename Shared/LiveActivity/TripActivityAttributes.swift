#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity tracking a connection on the Lock Screen and in the Dynamic Island.
struct TripActivityAttributes: ActivityAttributes {
    struct Step: Codable, Hashable, Sendable {
        var line: String
        var vehicle: Int
        var direction: String
        var fromStop: String
        var toStop: String
        var departure: Date
        var arrival: Date
        var platform: String?
        /// Seconds of current delay, if known.
        var delay: Int?

        var vehicleType: VehicleType { VehicleType(apiValue: vehicle) }
        var realDeparture: Date { departure.addingTimeInterval(TimeInterval(max(0, delay ?? 0))) }
        var realArrival: Date { arrival.addingTimeInterval(TimeInterval(max(0, delay ?? 0))) }
    }

    struct ContentState: Codable, Hashable, Sendable {
        var steps: [Step]
        var departure: Date
        var arrival: Date

        /// The ride to focus on: the one in progress or the next one.
        func currentStepIndex(at date: Date) -> Int {
            steps.firstIndex { $0.realArrival > date } ?? max(0, steps.count - 1)
        }
    }

    var title: String
    var connectionID: Int
}

extension TripActivityAttributes.ContentState {
    init(_ connection: Connection) {
        steps = connection.rides.map { ride in
            .init(
                line: ride.line,
                vehicle: ride.vehicle.rawValue,
                direction: ride.direction,
                fromStop: ride.boardStop?.name ?? "",
                toStop: ride.alightStop?.name ?? "",
                departure: ride.departure,
                arrival: ride.arrival,
                platform: ride.boardPlatform,
                delay: ride.delay)
        }
        departure = connection.departure
        arrival = connection.arrival.addingTimeInterval(TimeInterval(max(0, connection.rides.last?.delay ?? 0)))
    }
}
#endif
