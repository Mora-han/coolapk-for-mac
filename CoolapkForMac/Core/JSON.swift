import Foundation

/// Lightweight dynamic JSON value. Coolapk responses mix strings and numbers for the same
/// field, so every accessor coerces instead of failing.
enum JSONValue: Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(any value: Any) {
        switch value {
        case let value as NSNull:
            _ = value
            self = .null
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.map { JSONValue(any: $0) })
        case let value as [String: Any]:
            self = .object(value.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }
}

@dynamicMemberLookup
struct JSON: Hashable {
    let value: JSONValue

    static let null = JSON(value: .null)

    init(value: JSONValue) { self.value = value }
    init(any: Any) { self.value = JSONValue(any: any) }

    init(data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        self.value = JSONValue(any: object)
    }

    subscript(dynamicMember key: String) -> JSON {
        if case let .object(dict) = value, let child = dict[key] { return JSON(value: child) }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case let .array(items) = value, items.indices.contains(index) { return JSON(value: items[index]) }
        return .null
    }

    var isNull: Bool { if case .null = value { return true }; return false }

    var string: String {
        switch value {
        case let .string(text): return text
        case let .number(number):
            if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
            return String(number)
        case let .bool(flag): return flag ? "1" : "0"
        default: return ""
        }
    }

    var optionalString: String? { isNull ? nil : string }

    var int: Int {
        switch value {
        case let .number(number): return Int(number)
        case let .string(text): return Int(text) ?? Int(Double(text) ?? 0)
        case let .bool(flag): return flag ? 1 : 0
        default: return 0
        }
    }

    /// IDs are integers in some payloads and strings in others.
    var identifier: String {
        switch value {
        case let .number(number): return String(Int(number))
        case let .string(text): return text
        default: return ""
        }
    }

    var double: Double {
        switch value {
        case let .number(number): return number
        case let .string(text): return Double(text) ?? 0
        default: return 0
        }
    }

    var bool: Bool {
        switch value {
        case let .bool(flag): return flag
        case let .number(number): return number != 0
        case let .string(text): return text == "1" || text.lowercased() == "true"
        default: return false
        }
    }

    var array: [JSON] {
        if case let .array(items) = value { return items.map { JSON(value: $0) } }
        return []
    }

    var dictionary: [String: JSON] {
        if case let .object(dict) = value { return dict.mapValues { JSON(value: $0) } }
        return [:]
    }

    var exists: Bool { !isNull }

    var date: Date? {
        let stamp = int
        guard stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(stamp))
    }
}
