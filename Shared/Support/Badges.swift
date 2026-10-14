import SwiftUI

/// Colored line label, e.g. a green "A" for metro A or a blue "136" for a bus.
struct LineBadge: View {
    let vehicle: VehicleType
    let line: String
    var size: Size = .regular
    var showsIcon = true

    enum Size { case small, regular, large }

    var body: some View {
        HStack(spacing: 3) {
            if showsIcon || vehicle == .walk {
                Image(systemName: vehicle.symbol)
                    .font(iconFont)
            }
            if vehicle != .walk {
                Text(label)
                    .font(textFont)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(vehicle.textColor(line: line))
        .padding(.horizontal, size == .small ? 5 : 7)
        .padding(.vertical, size == .small ? 2 : 4)
        .frame(minWidth: size == .small ? 24 : 34)
        .background(vehicle.color(line: line), in: .rect(cornerRadius: size == .small ? 5 : 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vehicle.name) \(label)")
    }

    /// Large badges show the full name (e.g. "Ex3 / rj 577"), others the short public line.
    private var label: String { size == .large ? line : LineName.short(line) }

    private var iconFont: Font {
        switch size {
        case .small: .system(size: 9, weight: .semibold)
        case .regular: .system(size: 11, weight: .semibold)
        case .large: .system(size: 14, weight: .semibold)
        }
    }

    private var textFont: Font {
        switch size {
        case .small: .system(size: 12, weight: .bold, design: .rounded)
        case .regular: .system(size: 14, weight: .bold, design: .rounded)
        case .large: .system(size: 17, weight: .bold, design: .rounded)
        }
    }
}

struct DelayBadge: View {
    let delay: Int?
    var compact = false

    var body: some View {
        if let delay {
            let minutes = Fmt.delayMinutes(delay)
            Text(minutes == 0 ? (compact ? "včas" : "bez zpoždění") : "+\(minutes) min")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DelayBadge.color(minutes))
                .accessibilityLabel(minutes == 0 ? "Bez zpoždění" : "Zpoždění \(minutes) minut")
        }
    }

    static func color(_ minutes: Int) -> Color {
        switch minutes {
        case 0: .green
        case 1...4: .orange
        default: .red
        }
    }
}

struct PlatformBadge: View {
    let platform: String

    var body: some View {
        Text(Platform.label(platform))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}

/// Compact list of the lines used: [B] › [58]
struct LegStrip: View {
    let legs: [Leg]
    var size: LineBadge.Size = .regular

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(rides.enumerated()), id: \.element.id) { index, ride in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                LineBadge(vehicle: ride.vehicle, line: ride.line, size: size)
            }
        }
    }

    private var rides: [RideLeg] { legs.compactMap { if case .ride(let r) = $0 { r } else { nil } } }
}

// MARK: - Journey bar

/// Proportional timeline of a connection: each ride is a colored segment sized by its
/// duration, walks are dotted and waits are gaps. Scales from a 5-minute hop to a
/// 10-hour journey with five changes.
struct JourneyBar: View {
    let legs: [Leg]
    var height: CGFloat = 22

    var body: some View {
        WeightedHStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentView(segment)
                    .layoutValue(key: SegmentWeight.self, value: segment.weight)
                    .layoutValue(key: SegmentMinWidth.self, value: segment.minWidth)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct Segment: Identifiable {
        enum Kind { case ride(RideLeg), walk, wait }
        let id: String
        let kind: Kind
        let duration: TimeInterval

        var weight: Double { max(duration, 60) }
        var minWidth: CGFloat {
            switch kind {
            case .ride: 26
            case .walk: 10
            case .wait: 4
            }
        }
    }

    private var segments: [Segment] {
        legs.compactMap { leg in
            switch leg {
            case .ride(let r): Segment(id: leg.id, kind: .ride(r), duration: leg.duration)
            case .walk: leg.duration >= 60 ? Segment(id: leg.id, kind: .walk, duration: leg.duration) : nil
            case .wait: leg.duration >= 60 ? Segment(id: leg.id, kind: .wait, duration: leg.duration) : nil
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment.kind {
        case .ride(let ride):
            let color = ride.vehicle.color(line: ride.line)
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .overlay {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 3) {
                            Image(systemName: ride.vehicle.symbol).font(.system(size: 10, weight: .semibold))
                            Text(ride.displayLine).font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        Text(ride.displayLine).font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: ride.vehicle.symbol).font(.system(size: 9, weight: .semibold))
                        Color.clear
                    }
                    .lineLimit(1)
                    .foregroundStyle(ride.vehicle.textColor(line: ride.line))
                    .padding(.horizontal, 3)
                }
        case .walk:
            ZStack {
                DottedLine()
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 4.5]))
                    .frame(height: 3)
                ViewThatFits(in: .horizontal) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                        .background(.background)
                    Color.clear
                }
            }
        case .wait:
            Capsule()
                .fill(.quaternary)
                .frame(height: 3)
        }
    }

    private var accessibilityText: String {
        legs.compactMap { leg -> String? in
            switch leg {
            case .ride(let r): "\(r.vehicle.name) \(r.displayLine), \(Fmt.duration(leg.duration))"
            case .walk: leg.duration >= 60 ? "pěšky \(Fmt.duration(leg.duration))" : nil
            case .wait: leg.duration >= 60 ? "čekání \(Fmt.duration(leg.duration))" : nil
            }
        }.joined(separator: ", ")
    }
}

private struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
        }
    }
}

private struct SegmentWeight: LayoutValueKey {
    static let defaultValue: Double = 1
}

private struct SegmentMinWidth: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Horizontal stack that distributes width proportionally to each child's weight,
/// while guaranteeing every child its minimum width.
struct WeightedHStack: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let minTotal = subviews.reduce(0) { $0 + $1[SegmentMinWidth.self] }
            + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: max(proposal.width ?? 280, minTotal), height: proposal.height ?? 22)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.widths(
            available: bounds.width - spacing * CGFloat(max(0, subviews.count - 1)),
            weights: subviews.map { $0[SegmentWeight.self] },
            minimums: subviews.map { $0[SegmentMinWidth.self] })
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    static func widths(available: CGFloat, weights: [Double], minimums: [CGFloat]) -> [CGFloat] {
        var fixed = [CGFloat?](repeating: nil, count: weights.count)
        while true {
            let freeWidth = available - fixed.compactMap { $0 }.reduce(0, +)
            let freeWeight = zip(weights, fixed).filter { $1 == nil }.reduce(0) { $0 + $1.0 }
            var changed = false
            for i in weights.indices where fixed[i] == nil {
                let w = freeWeight > 0 ? freeWidth * CGFloat(weights[i] / freeWeight) : 0
                if w < minimums[i] {
                    fixed[i] = minimums[i]
                    changed = true
                }
            }
            if !changed {
                return weights.indices.map { i in
                    fixed[i] ?? (freeWeight > 0 ? max(0, freeWidth * CGFloat(weights[i] / freeWeight)) : 0)
                }
            }
        }
    }
}
