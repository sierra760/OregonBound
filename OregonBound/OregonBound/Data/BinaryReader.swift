import Foundation

/// Bounds-checked big-endian and little-endian field access over immutable bytes.
struct BinaryReader {
    enum Failure: Error, CustomStringConvertible {
        case truncated(offset: Int, length: Int, available: Int)
        var description: String {
            switch self {
            case .truncated(let offset, let length, let available):
                return "Field at byte \(offset) requires \(length) bytes; only \(available) available"
            }
        }
    }

    let bytes: [UInt8]
    init(_ data: Data) { bytes = [UInt8](data) }
    init(bytes: [UInt8]) { self.bytes = bytes }
    var count: Int { bytes.count }

    func require(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset + length <= bytes.count else {
            throw Failure.truncated(offset: offset, length: length, available: max(0, bytes.count - offset))
        }
    }
    func u8(_ offset: Int) throws -> UInt8 { try require(offset, 1); return bytes[offset] }
    func i8(_ offset: Int) throws -> Int8 { Int8(bitPattern: try u8(offset)) }
    func u16(_ offset: Int) throws -> UInt16 {
        try require(offset, 2)
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
    func i16(_ offset: Int) throws -> Int16 { Int16(bitPattern: try u16(offset)) }
    func u32(_ offset: Int) throws -> UInt32 {
        try require(offset, 4)
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
    func i32(_ offset: Int) throws -> Int32 { Int32(bitPattern: try u32(offset)) }
    func u16LE(_ offset: Int) throws -> UInt16 {
        try require(offset, 2)
        return UInt16(bytes[offset + 1]) << 8 | UInt16(bytes[offset])
    }
    func slice(_ offset: Int, _ length: Int) throws -> [UInt8] {
        try require(offset, length)
        return Array(bytes[offset..<offset + length])
    }
    func data(_ offset: Int, _ length: Int) throws -> Data { Data(try slice(offset, length)) }
    /// Pascal string: one length byte followed by Mac Roman text.
    func pascalString(_ offset: Int) throws -> (text: String, length: Int) {
        let length = Int(try u8(offset))
        return (MacRoman.decode(try slice(offset + 1, length)), 1 + length)
    }
}

enum MacRoman {
    static func decode<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        String(data: Data(bytes), encoding: .macOSRoman) ?? String(decoding: Data(bytes), as: UTF8.self)
    }
    static func encode(_ text: String) -> [UInt8]? { text.data(using: .macOSRoman).map(Array.init) }
}

extension Data {
    /// Big-endian helpers for writers.
    mutating func appendU16(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 0xff)) }
    mutating func appendU32(_ value: UInt32) { appendU16(UInt16(value >> 16)); appendU16(UInt16(value & 0xffff)) }
    mutating func appendU16LE(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func appendU32LE(_ value: UInt32) { appendU16LE(UInt16(value & 0xffff)); appendU16LE(UInt16(value >> 16)) }
}
