import Foundation

/// All times are shown in Prague time regardless of the device time zone.
enum Fmt {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = RPCDate.prague
        f.dateFormat = "H:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.timeZone = RPCDate.prague
        f.dateFormat = "EEEE d. M."
        return f
    }()

    static func time(_ date: Date?) -> String {
        date.map(timeFormatter.string(from:)) ?? "–"
    }

    static func day(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = RPCDate.prague
        if cal.isDateInToday(date) { return "dnes" }
        if cal.isDateInTomorrow(date) { return "zítra" }
        return dayFormatter.string(from: date)
    }

    /// Number of calendar days between two dates in Prague (nil when same day).
    static func dayOffset(from start: Date, to end: Date) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = RPCDate.prague
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
        return days > 0 ? days : nil
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func distance(_ meters: Int) -> String {
        meters < 1000
            ? "\(meters) m"
            : (Double(meters) / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }

    /// "za 5 min", "teď", "za 1 h 10 min"
    static func countdown(to date: Date, now: Date = .now) -> String {
        let interval = date.timeIntervalSince(now)
        if interval < -60 { return "odjelo" }
        let minutes = Int((interval / 60).rounded(.down))
        if minutes <= 0 { return "teď" }
        if minutes < 60 { return "za \(minutes) min" }
        return "za " + duration(Double(minutes) * 60)
    }

    /// Compact countdown for widgets: "teď", "7 min", or the clock time when far away.
    static func shortCountdown(to date: Date, now: Date = .now) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.down))
        if minutes <= 0 { return "teď" }
        if minutes < 60 { return "\(minutes) min" }
        return time(date)
    }

    /// "za 12 min" when soon, otherwise "zítra v 7:32" / "v 14:05".
    static func departureHint(to date: Date, now: Date = .now) -> String {
        if date.timeIntervalSince(now) < 3 * 3600 { return countdown(to: date, now: now) }
        let d = day(date)
        return d == "dnes" ? "v \(time(date))" : "\(d) v \(time(date))"
    }

    static func transfers(_ count: Int) -> String {
        switch count {
        case 0: "přímé"
        case 1: "1 přestup"
        case 2...4: "\(count) přestupy"
        default: "\(count) přestupů"
        }
    }

    static func stops(_ count: Int) -> String {
        switch count {
        case 1: "1 zastávka"
        case 2...4: "\(count) zastávky"
        default: "\(count) zastávek"
        }
    }

    /// Delay in whole minutes, rounding half-minutes towards the passenger's worst case.
    static func delayMinutes(_ seconds: Int) -> Int {
        seconds <= 0 ? 0 : Int((Double(seconds) / 60).rounded())
    }
}
