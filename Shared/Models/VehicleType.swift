import SwiftUI

enum VehicleType: Int, Codable, Sendable, CaseIterable, Hashable {
    case walk = 0
    case bus = 1
    case tram = 2
    case cable = 3
    case metro = 4
    case ferry = 5
    case trolley = 6
    case train = 7

    init(apiValue: Int?) {
        self = VehicleType(rawValue: apiValue ?? 0) ?? .walk
    }

    /// Transport modes the user can filter by, in display order.
    static let selectable: [VehicleType] = [.metro, .tram, .bus, .train, .trolley, .ferry, .cable]

    /// Key used by the API in the search options struct.
    var apiKey: String {
        switch self {
        case .walk: "walk"
        case .bus: "bus"
        case .tram: "tram"
        case .cable: "cable"
        case .metro: "metro"
        case .ferry: "ferry"
        case .trolley: "trolley"
        case .train: "train"
        }
    }

    var name: String {
        switch self {
        case .walk: "Pěšky"
        case .bus: "Autobus"
        case .tram: "Tramvaj"
        case .cable: "Lanovka"
        case .metro: "Metro"
        case .ferry: "Loď"
        case .trolley: "Trolejbus"
        case .train: "Vlak"
        }
    }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .bus: "bus.fill"
        case .tram: "tram.fill"
        case .cable: "cablecar.fill"
        case .metro: "tram.fill.tunnel"
        case .ferry: "ferry.fill"
        case .trolley: "bus.doubledecker.fill"
        case .train: "train.side.front.car"
        }
    }

    var baseColor: Color {
        switch self {
        case .walk: Color(.systemGray)
        case .bus: Color(hex: 0x1F6FEB)
        case .tram: Color(hex: 0xE8590C)
        case .cable: Color(hex: 0x7048E8)
        case .metro: Color(hex: 0x343A40)
        case .ferry: Color(hex: 0x1098AD)
        case .trolley: Color(hex: 0x0CA678)
        case .train: Color(hex: 0x1C3F94)
        }
    }

    /// Color for a concrete line – Prague metro lines keep their official colors.
    func color(line: String) -> Color {
        guard self == .metro else { return baseColor }
        switch line.uppercased() {
        case "A": return Color(hex: 0x1BA94C)
        case "B": return Color(hex: 0xF5B400)
        case "C": return Color(hex: 0xE03131)
        case "D": return Color(hex: 0x1E90D6)
        default: return baseColor
        }
    }

    func textColor(line: String) -> Color {
        self == .metro && line.uppercased() == "B" ? .black : .white
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
