import ActivityKit
import Foundation
import Observation

/// Starts, updates and ends trip-tracking Live Activities.
@MainActor @Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private(set) var trackedIDs: Set<Int> = []
    private(set) var lastError: String?

    private init() {
        trackedIDs = Set(Activity<TripActivityAttributes>.activities.map(\.attributes.connectionID))
    }

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isTracking(_ id: Connection.ID) -> Bool { trackedIDs.contains(id) }

    func start(_ connection: Connection, title: String) {
        // One trip at a time keeps the Lock Screen tidy.
        Task {
            for activity in Activity<TripActivityAttributes>.activities
            where activity.attributes.connectionID != connection.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        let attributes = TripActivityAttributes(title: title, connectionID: connection.id)
        let state = TripActivityAttributes.ContentState(connection)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.arrival.addingTimeInterval(600)))
            trackedIDs = [connection.id]
            lastError = nil
        } catch {
            lastError = "Živou aktivitu se nepodařilo spustit."
        }
    }

    func update(_ connection: Connection) {
        guard trackedIDs.contains(connection.id) else { return }
        let state = TripActivityAttributes.ContentState(connection)
        let id = connection.id
        Task {
            for activity in Activity<TripActivityAttributes>.activities where activity.attributes.connectionID == id {
                if state.arrival < .now.addingTimeInterval(-300) {
                    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
                } else {
                    await activity.update(ActivityContent(state: state, staleDate: state.arrival.addingTimeInterval(600)))
                }
            }
        }
        if state.arrival < .now.addingTimeInterval(-300) { trackedIDs.remove(id) }
    }

    func stop(_ id: Connection.ID) {
        Task {
            for activity in Activity<TripActivityAttributes>.activities where activity.attributes.connectionID == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        trackedIDs.remove(id)
    }
}
