import SwiftUI

/// Colored line label, e.g. a green "A" for metro A or a blue "136" for a bus.
struct LineBadge: View {
    let vehicle: VehicleType
    let line: String
    var size: Size = .regular

    enum Size { case small, regular, large }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: vehicle.symbol)
                .font(iconFont)
            if vehicle != .walk {
                Text(shortLine)
                    .font(textFont)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(vehicle.textColor(line: line))
        .padding(.horizontal, size == .small ? 5 : 7)
        .padding(.vertical, size == .small ? 2 : 4)
        .frame(minWidth: size == .small ? 26 : 34)
        .background(vehicle.color(line: line), in: .rect(cornerRadius: size == .small ? 5 : 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vehicle.name) \(line)")
    }

    /// Train names like "Ex3 / rj 577" are shortened to the public line ("Ex3").
    private var shortLine: String {
        guard size != .large else { return line }
        return line.components(separatedBy: " / ").first ?? line
    }

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
                .foregroundStyle(color(minutes))
                .accessibilityLabel(minutes == 0 ? "Bez zpoždění" : "Zpoždění \(minutes) minut")
        }
    }

    private func color(_ minutes: Int) -> Color {
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

/// Compact overview of a connection's legs: [C] › [A] › 🚶
struct LegStrip: View {
    let legs: [Leg]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(visibleLegs.enumerated()), id: \.element.id) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                switch leg {
                case .ride(let ride):
                    LineBadge(vehicle: ride.vehicle, line: ride.line)
                case .walk(let walk):
                    HStack(spacing: 1) {
                        Image(systemName: "figure.walk")
                        Text("\(Int((walk.arrival.timeIntervalSince(walk.departure) / 60).rounded()))")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Hides negligible walks (< 2 min) between rides to keep the strip readable.
    private var visibleLegs: [Leg] {
        legs.filter { leg in
            guard case .walk(let w) = leg else { return true }
            return w.arrival.timeIntervalSince(w.departure) >= 120
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack {
            LineBadge(vehicle: .metro, line: "A")
            LineBadge(vehicle: .metro, line: "B")
            LineBadge(vehicle: .metro, line: "C")
            LineBadge(vehicle: .tram, line: "22")
            LineBadge(vehicle: .bus, line: "136")
            LineBadge(vehicle: .train, line: "Ex3 / rj 577")
        }
        HStack {
            DelayBadge(delay: 0)
            DelayBadge(delay: 180)
            DelayBadge(delay: 2160)
            PlatformBadge(platform: "4 / 14")
        }
    }
    .padding()
}
