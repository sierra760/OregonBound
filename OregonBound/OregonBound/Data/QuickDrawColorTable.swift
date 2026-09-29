import Foundation

// Port of scripts/graphics_extract/palette.py plus the PixMap / color-table
// helpers from scripts/graphics_extract/imag_codec.py. Error descriptions
// mirror the reference Python pipeline's `struct.error`, `IndexError` and
// `ValueError` text so manifest diagnostics stay byte-identical.

/// Failures whose descriptions match the Python reference pipeline verbatim.
enum ReferenceDecodeError: Error, CustomStringConvertible {
    /// `struct.unpack_from` past the end of a buffer.
    case unpack(offset: Int, size: Int, actual: Int)
    /// `bytes[index]` past the end of a buffer.
    case indexOutOfRange
    /// Integer division by zero.
    case divisionByZero
    /// `ValueError(message)`.
    case value(String)

    var description: String {
        switch self {
        case .unpack(let offset, let size, let actual):
            return "unpack_from requires a buffer of at least \(offset + size) bytes for unpacking \(size) bytes at offset \(offset) (actual buffer size is \(actual))"
        case .indexOutOfRange:
            return "index out of range"
        case .divisionByZero:
            return "division by zero"
        case .value(let message):
            return message
        }
    }
}

/// Byte accessors with Python semantics: fixed-width fields fail like
/// `struct.unpack_from`, single-byte reads fail like `bytes[i]`, and slices
/// clamp silently like `bytes[a:b]`.
struct ByteSource {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }
    init(_ data: Data) { self.bytes = [UInt8](data) }

    var count: Int { bytes.count }

    /// Python `bytes[:end]` view (end clamped to the buffer).
    func prefix(_ end: Int) -> ByteSource {
        ByteSource(Array(bytes[0..<max(0, min(end, bytes.count))]))
    }

    /// Fails like `struct.unpack_from` would for a `size`-byte format at `offset`.
    func requireUnpack(_ offset: Int, _ size: Int) throws {
        guard offset >= 0, offset + size <= bytes.count else {
            throw ReferenceDecodeError.unpack(offset: offset, size: size, actual: bytes.count)
        }
    }
    private func check(_ offset: Int, _ size: Int) throws { try requireUnpack(offset, size) }

    func byte(_ index: Int) throws -> UInt8 {
        guard index >= 0, index < bytes.count else { throw ReferenceDecodeError.indexOutOfRange }
        return bytes[index]
    }
    func u16(_ offset: Int) throws -> UInt16 {
        try check(offset, 2)
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
    func i16(_ offset: Int) throws -> Int16 { Int16(bitPattern: try u16(offset)) }
    func u32(_ offset: Int) throws -> UInt32 {
        try check(offset, 4)
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }
    func u16LE(_ offset: Int) throws -> UInt16 {
        try check(offset, 2)
        return UInt16(bytes[offset + 1]) << 8 | UInt16(bytes[offset])
    }
    /// Four big-endian signed shorts (`>hhhh`).
    func rect(_ offset: Int) throws -> QuickDrawRect {
        try check(offset, 8)
        return QuickDrawRect(top: Int(try i16(offset)), left: Int(try i16(offset + 2)),
                             bottom: Int(try i16(offset + 4)), right: Int(try i16(offset + 6)))
    }
    /// Python `bytes[start:end]`: negative or out-of-range bounds clamp.
    func slice(_ start: Int, _ end: Int) -> ArraySlice<UInt8> {
        let lower = max(0, min(start, bytes.count))
        let upper = max(lower, min(end, bytes.count))
        return bytes[lower..<upper]
    }
}

struct QuickDrawRect: Equatable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int
    var width: Int { right - left }
    var height: Int { bottom - top }
}

struct RGBColor: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}

/// Parsed QuickDraw PixMap header fields (palette.parse_pixmap / imag_codec.parse_pixmap).
struct QuickDrawPixMap {
    static let cicnOffset = 0
    static let imagOffset = 6

    let rowBytes: Int
    let isPixMap: Bool
    let bounds: QuickDrawRect
    let pixelSize: Int
    var width: Int { bounds.width }
    var height: Int { bounds.height }

    /// Reads the PixMap at `offset`, failing like Python's `struct.unpack_from`.
    init(parsing source: ByteSource, at offset: Int) throws {
        let rowBytesRaw = try source.u16(offset + 4)
        rowBytes = Int(rowBytesRaw & 0x3FFF)
        isPixMap = rowBytesRaw & 0x8000 != 0
        bounds = try source.rect(offset + 6)
        pixelSize = Int(try source.u16(offset + 32))
    }

    /// Python `repr()` of the parse_pixmap dictionary, used in error text.
    var pythonDescription: String {
        "{'row_bytes': \(rowBytes), 'is_pixmap': \(isPixMap ? "True" : "False"), "
            + "'bounds': (\(bounds.top), \(bounds.left), \(bounds.bottom), \(bounds.right)), "
            + "'width': \(width), 'height': \(height), 'pixel_size': \(pixelSize)}"
    }
}

enum QuickDrawColorTable {
    static let headerLength = 8

    /// palette.parse_color_table: validated color list (value fields ignored).
    static func parse(_ source: ByteSource, at offset: Int) throws -> [RGBColor] {
        if source.count < offset + headerLength {
            throw ReferenceDecodeError.value(
                "Color table header at offset \(offset) requires \(headerLength) bytes; "
                + "only \(max(0, source.count - offset)) available")
        }
        try source.requireUnpack(offset, 8)  // ">IHH"
        let ctSize = Int(try source.u16(offset + 6))
        let expectedLength = headerLength + (ctSize + 1) * 8
        if source.count < offset + expectedLength {
            throw ReferenceDecodeError.value(
                "Color table entries at offset \(offset) declare \(ctSize + 1) entries "
                + "(\(expectedLength) bytes total); only \(max(0, source.count - offset)) available")
        }
        var colors: [RGBColor] = []
        colors.reserveCapacity(ctSize + 1)
        for index in 0...ctSize {
            colors.append(try color(source, at: offset + headerLength + index * 8))
        }
        return colors
    }

    /// cicn._parse_color_table_by_value: colors keyed by their `value` field.
    static func parseByValue(_ source: ByteSource, at offset: Int) throws -> (colors: [UInt16: RGBColor], entryCount: Int) {
        try requireAvailable(source, offset, headerLength, "cicn color table header")
        let ctSize = Int(try source.u16(offset + 6))
        let entryCount = ctSize + 1
        try requireAvailable(source, offset, headerLength + entryCount * 8, "cicn color table")
        var colors: [UInt16: RGBColor] = [:]
        for index in 0..<entryCount {
            let entry = offset + headerLength + index * 8
            colors[try source.u16(entry)] = try color(source, at: entry)
        }
        return (colors, entryCount)
    }

    /// cicn._require_available.
    static func requireAvailable(_ source: ByteSource, _ offset: Int, _ length: Int, _ label: String) throws {
        if length < 0 { throw ReferenceDecodeError.value("\(label) length cannot be negative") }
        if source.count < offset + length {
            throw ReferenceDecodeError.value(
                "\(label) at offset \(offset) requires \(length) bytes; only \(max(0, source.count - offset)) available")
        }
    }

    /// palette.build_palette_bytes: 768-byte RGB palette from a color list.
    static func paletteBytes(_ colors: [RGBColor]) -> [UInt8] {
        var palette = [UInt8](repeating: 0, count: 256 * 3)
        for (index, color) in colors.prefix(256).enumerated() {
            palette[index * 3] = color.red
            palette[index * 3 + 1] = color.green
            palette[index * 3 + 2] = color.blue
        }
        return palette
    }

    /// imag_codec.build_palette_from_ctable / build_palette_from_clut: 768-byte
    /// palette read straight from a color table without length validation
    /// beyond the fields actually touched.
    static func paletteBytes(fromColorTable source: ByteSource, at offset: Int) throws -> [UInt8] {
        try source.requireUnpack(offset, 8)  // ">IHH"
        let ctSize = Int(try source.u16(offset + 6))
        var palette = [UInt8](repeating: 0, count: 256 * 3)
        for index in 0..<min(ctSize + 1, 256) {
            let color = try color(source, at: offset + headerLength + index * 8)
            palette[index * 3] = color.red
            palette[index * 3 + 1] = color.green
            palette[index * 3 + 2] = color.blue
        }
        return palette
    }

    /// imag_codec.detect_inline_ctable: whether a color table follows the first
    /// frame's PixMap at `offset`, and its byte size.
    static func detectInlineColorTable(_ source: ByteSource, at offset: Int) -> (present: Bool, byteSize: Int) {
        guard source.count >= offset + headerLength,
              let flags = try? source.u16(offset + 4),
              let sizeField = try? source.u16(offset + 6) else { return (false, 0) }
        let entries = Int(sizeField) + 1
        let byteSize = headerLength + entries * 8
        if flags == 0x8000 && entries <= 256 && source.count >= offset + byteSize {
            return (true, byteSize)
        }
        return (false, 0)
    }

    /// One ColorSpec entry: value, then 16-bit red/green/blue reduced to 8 bits.
    private static func color(_ source: ByteSource, at entry: Int) throws -> RGBColor {
        try source.requireUnpack(entry, 8)  // ">HHHH"
        return RGBColor(red: UInt8(try source.u16(entry + 2) >> 8),
                 green: UInt8(try source.u16(entry + 4) >> 8),
                 blue: UInt8(try source.u16(entry + 6) >> 8))
    }
}
