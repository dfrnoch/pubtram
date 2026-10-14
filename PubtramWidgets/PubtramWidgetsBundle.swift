import SwiftUI
import WidgetKit

@main
struct PubtramWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DeparturesWidget()
        RouteWidget()
        TripLiveActivity()
    }
}

/// Header used by all home-screen widgets.
struct WidgetHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

struct WidgetMessage: View {
    let text: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Date {
    /// Builds minute-by-minute timeline dates so countdowns stay accurate.
    static func minuteSteps(from start: Date = .now, count: Int) -> [Date] {
        let base = Calendar.current.dateInterval(of: .minute, for: start)?.start ?? start
        return (0..<count).map { base.addingTimeInterval(Double($0) * 60) }
    }
}
