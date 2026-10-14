import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island for a tracked trip.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(DeepLink.search.url)
        } dynamicIsland: { context in
            let state = context.state
            let index = state.currentStepIndex(at: .now)
            let step = state.steps[safe: index]
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let step {
                        LineBadge(vehicle: step.vehicleType, line: step.line)
                            .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let step {
                        StepTimer(step: step)
                            .font(.title3.weight(.semibold))
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let step {
                        Text("směr \(step.direction)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let step {
                        StepDetail(step: step, next: state.steps[safe: index + 1], arrival: state.arrival)
                    }
                }
            } compactLeading: {
                if let step {
                    LineBadge(vehicle: step.vehicleType, line: step.line, size: .small, showsIcon: false)
                }
            } compactTrailing: {
                if let step {
                    StepTimer(step: step)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: step?.vehicleType.symbol ?? "tram.fill")
                    .foregroundStyle(step.map { $0.vehicleType.color(line: $0.line) } ?? .accentColor)
            }
            .widgetURL(DeepLink.search.url)
        }
    }
}

/// Counts down to boarding, then to getting off.
private struct StepTimer: View {
    let step: TripActivityAttributes.Step

    var body: some View {
        let now = Date.now
        let target = now < step.realDeparture ? step.realDeparture : step.realArrival
        Text(timerInterval: now...max(now, target), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

private struct StepDetail: View {
    let step: TripActivityAttributes.Step
    let next: TripActivityAttributes.Step?
    let arrival: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(Date.now < step.realDeparture ? "Nástup" : "Výstup")
                    .foregroundStyle(.secondary)
                Text(Date.now < step.realDeparture ? step.fromStop : step.toStop)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let platform = step.platform, Date.now < step.realDeparture {
                    Text(Platform.label(platform)).foregroundStyle(.secondary)
                }
            }
            if let next {
                HStack(spacing: 4) {
                    Text("Pak").foregroundStyle(.secondary)
                    LineBadge(vehicle: next.vehicleType, line: next.line, size: .small)
                    Text("v \(Fmt.time(next.realDeparture)) z \(next.fromStop)").lineLimit(1)
                }
            } else {
                Text("V cíli v \(Fmt.time(arrival))").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripLockScreenView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState

    var body: some View {
        let index = state.currentStepIndex(at: .now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(attributes.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("v cíli \(Fmt.time(state.arrival))")
                    .font(.caption.weight(.semibold))
            }

            if let step = state.steps[safe: index] {
                HStack(alignment: .center, spacing: 10) {
                    LineBadge(vehicle: step.vehicleType, line: step.line, size: .large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("směr \(step.direction)")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(Date.now < step.realDeparture
                            ? "z \(step.fromStop)\(step.platform.map { " · " + Platform.label($0) } ?? "")"
                            : "vystupte: \(step.toStop)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Date.now < step.realDeparture ? "odjezd" : "výstup")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        StepTimer(step: step)
                            .font(.title2.weight(.bold))
                    }
                }
            }

            ProgressView(timerInterval: state.departure...max(state.departure.addingTimeInterval(60), state.arrival), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.accentColor)

            if state.steps.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(state.steps.enumerated()), id: \.offset) { i, step in
                        if i > 0 {
                            Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        LineBadge(vehicle: step.vehicleType, line: step.line, size: .small)
                            .opacity(i < index ? 0.4 : 1)
                        Text(Fmt.time(step.realDeparture))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}
