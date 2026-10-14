import Foundation

/// A value in Seznam's FastRPC / XML-RPC protocol.
///
/// The Seznam timetable backend speaks binary FastRPC, but it also accepts and
/// returns plain XML-RPC, which is what we use here (no third-party codec needed).
enum RPCValue: Sendable, Equatable {
    case int(Int)
    case bool(Bool)
    case double(Double)
    case string(String)
    case date(Date)
    case array([RPCValue])
    case dict([String: RPCValue])
    case null

    subscript(key: String) -> RPCValue? {
        if case .dict(let d) = self { return d[key] }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let v): v
        case .double(let v): Int(v)
        case .bool(let v): v ? 1 : 0
        case .string(let v): Int(v)
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .double(let v): v
        case .int(let v): Double(v)
        case .string(let v): Double(v)
        default: nil
        }
    }

    var string: String? {
        switch self {
        case .string(let v): v
        case .int(let v): String(v)
        default: nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let v): v
        case .int(let v): v != 0
        default: nil
        }
    }

    var array: [RPCValue] { if case .array(let a) = self { a } else { [] } }

    /// ISO-8601 strings such as `2026-10-15T08:01:40+02:00`.
    var isoDate: Date? {
        guard let s = string else { return nil }
        return RPCDate.parseISO(s)
    }
}

extension RPCValue: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(integerLiteral value: Int) { self = .int(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(arrayLiteral elements: RPCValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, RPCValue)...) {
        self = .dict(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}

enum RPCDate {
    static let prague = TimeZone(identifier: "Europe/Prague")!

    /// XML-RPC `dateTime.iso8601` has no zone; the server interprets it as Prague local time.
    static func xmlRPCString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = prague
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d:%02d:%02d",
            c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    static func parseISO(_ s: String) -> Date? {
        try? Date.ISO8601FormatStyle().parse(s)
    }

    static func parseXMLRPC(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = parseISO(trimmed) { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = prague
        for format in ["yyyyMMdd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyyMMdd'T'HH:mm:ssZZZZZ"] {
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }
}

// MARK: - Encoding

enum XMLRPCEncoder {
    static func methodCall(_ method: String, params: [RPCValue]) -> Data {
        var out = "<?xml version=\"1.0\"?><methodCall><methodName>\(escape(method))</methodName><params>"
        for p in params {
            out += "<param>"
            encode(p, into: &out)
            out += "</param>"
        }
        out += "</params></methodCall>"
        return Data(out.utf8)
    }

    private static func encode(_ value: RPCValue, into out: inout String) {
        out += "<value>"
        switch value {
        case .int(let v): out += "<i4>\(v)</i4>"
        case .bool(let v): out += "<boolean>\(v ? 1 : 0)</boolean>"
        case .double(let v): out += "<double>\(v)</double>"
        case .string(let v): out += "<string>\(escape(v))</string>"
        case .date(let d): out += "<dateTime.iso8601>\(RPCDate.xmlRPCString(d))</dateTime.iso8601>"
        case .null: out += "<nil/>"
        case .array(let a):
            out += "<array><data>"
            for v in a { encode(v, into: &out) }
            out += "</data></array>"
        case .dict(let d):
            out += "<struct>"
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                out += "<member><name>\(escape(k))</name>"
                encode(v, into: &out)
                out += "</member>"
            }
            out += "</struct>"
        }
        out += "</value>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Decoding

struct RPCFault: Error, LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

final class XMLRPCDecoder: NSObject, XMLParserDelegate {
    private enum Frame {
        case array([RPCValue])
        case dict([String: RPCValue], pendingName: String?)
    }

    private var stack: [Frame] = []
    private var text = ""
    private var pending: RPCValue?
    private var result: RPCValue?
    private var isFault = false
    private var parseError: Error?

    static func decode(_ data: Data) throws -> RPCValue {
        let decoder = XMLRPCDecoder()
        let parser = XMLParser(data: data)
        parser.delegate = decoder
        guard parser.parse() else {
            throw decoder.parseError ?? parser.parserError ?? URLError(.cannotParseResponse)
        }
        guard let result = decoder.result else { throw URLError(.cannotParseResponse) }
        if decoder.isFault {
            throw RPCFault(code: result["faultCode"]?.int ?? -1, message: result["faultString"]?.string ?? "Fault")
        }
        return result
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        switch name {
        case "value": pending = nil
        case "struct": stack.append(.dict([:], pendingName: nil))
        case "array": stack.append(.array([]))
        case "fault": isFault = true
        case "nil": pending = .null
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "i4", "int", "i8": pending = .int(Int(text.trimmingCharacters(in: .whitespaces)) ?? 0)
        case "boolean": pending = .bool(text.trimmingCharacters(in: .whitespaces) == "1")
        case "double": pending = .double(Double(text.trimmingCharacters(in: .whitespaces)) ?? 0)
        case "string": pending = .string(text)
        case "dateTime.iso8601":
            pending = RPCDate.parseXMLRPC(text).map(RPCValue.date) ?? .string(text)
        case "base64": pending = .string(text)
        case "name":
            if case .dict(let d, _) = stack.last {
                stack[stack.count - 1] = .dict(d, pendingName: text)
            }
        case "struct":
            if case .dict(let d, _) = stack.popLast() { pending = .dict(d) }
        case "array":
            if case .array(let a) = stack.popLast() { pending = .array(a) }
        case "value":
            let value = pending ?? .string(text)
            pending = nil
            switch stack.last {
            case .array(var a):
                a.append(value)
                stack[stack.count - 1] = .array(a)
            case .dict(var d, let key):
                if let key { d[key] = value }
                stack[stack.count - 1] = .dict(d, pendingName: nil)
            case nil:
                result = value
            }
        default: break
        }
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error
    }
}
