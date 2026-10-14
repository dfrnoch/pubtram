import CoreLocation

/// Decodes Mapy.cz's compact polyline encoding (`SMap.Coords.stringToCoords`).
///
/// Each coordinate component is either an absolute 28-bit value (5 chars),
/// or a delta encoded in 3 or 2 chars, using a custom base-64 alphabet.
enum GeometryDecoder {
    private static let alphabet = Array("0ABCD2EFGH4IJKLMN6OPQRST8UVWXYZ-1abcd3efgh5ijklmn7opqrst9uvwxyz.")
    private static let lookup: [Character: Int] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    static func decode(_ string: String) -> [CLLocationCoordinate2D] {
        let chars = Array(string)
        var i = 0
        var coords = [0, 0]
        var index = 0
        var result: [CLLocationCoordinate2D] = []

        func read(_ count: Int) -> Int? {
            var value = 0
            var remaining = count
            while remaining > 0 {
                guard i < chars.count else { return nil }
                let ch = chars[i]
                i += 1
                guard let digit = lookup[ch] else { continue }
                value = (value << 6) + digit
                remaining -= 1
            }
            return value
        }

        while i < chars.count {
            guard var num = read(1) else { break }
            if num & 48 == 48 {
                num -= 48
                guard let rest = read(4) else { break }
                coords[index] = ((num & 15) << 24) + rest
            } else if num & 32 == 32 {
                guard let rest = read(2) else { break }
                coords[index] += ((num & 15) << 12) + rest - (1 << 15)
            } else {
                guard let rest = read(1) else { break }
                coords[index] += ((num & 31) << 6) + rest - (1 << 10)
            }
            if index == 1 {
                let lon = Double(coords[0]) * 360 / Double(1 << 28) - 180
                let lat = Double(coords[1]) * 180 / Double(1 << 28) - 90
                result.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            index = (index + 1) % 2
        }
        return result
    }
}
