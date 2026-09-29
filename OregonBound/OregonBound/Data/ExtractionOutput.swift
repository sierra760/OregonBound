import Foundation

/// Destination folder for imported game data. Relative paths mirror the
/// layout produced by the reference Python pipeline (scripts/), so verification
/// can diff the two trees.
struct ExtractionOutput {
    let root: URL

    func url(_ relativePath: String) -> URL { root.appendingPathComponent(relativePath) }

    func write(_ data: Data, to relativePath: String) throws {
        let destination = url(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    func writeJSON<T: Encodable>(_ value: T, to relativePath: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try write(data, to: relativePath)
    }

    func writePNG(_ image: PNGEncoder.Image, to relativePath: String) throws {
        try write(try PNGEncoder.encode(image), to: relativePath)
    }
}

/// Loosely typed JSON value for extractor records whose fields mix types.
enum JSONValue: Encodable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    init(nilLiteral: ()) { self = .null }
}

extension Data {
    var hexDigest: String { map { String(format: "%02x", $0) }.joined() }
}
