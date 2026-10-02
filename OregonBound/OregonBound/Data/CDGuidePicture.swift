import Foundation

/// Bounded QuickDraw picture data for the CD's standalone reader. No original
/// picture bytes or font glyphs are built into the application.
struct CDGuidePicture {
    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let detail): return "Invalid guide picture: \(detail)" }
        }
    }

    struct Point: Equatable {
        var x: Int
        var y: Int
        static let zero = Point(x: 0, y: 0)
        func adding(_ other: Point) -> Point {
            Point(x: Int(Int16(truncatingIfNeeded: x + other.x)),
                  y: Int(Int16(truncatingIfNeeded: y + other.y)))
        }
    }
    struct Color: Equatable {
        let red: UInt16
        let green: UInt16
        let blue: UInt16
        static let black = Color(red: 0, green: 0, blue: 0)
        static let white = Color(red: 65535, green: 65535, blue: 65535)
    }
    struct GlyphState: Equatable {
        var outlinePreferred = false
        var preserveGlyph = false
        var fractionalWidths = false
        var scalingDisabled = false
    }
    struct State: Equatable {
        var origin = Point.zero
        var clip: Region
        var foreground = Color.black
        var background = Color.white
        var font = 0
        var face: UInt8 = 0
        var size = 12
        var spaceExtra: Int32 = 0
        var characterExtra: Int16 = 0
        var numerator = Point(x: 1, y: 1)
        var denominator = Point(x: 1, y: 1)
        var textMode: UInt16 = 1
        var glyphs = GlyphState()
        var penSize = Point(x: 1, y: 1)
        var penMode: UInt16 = 8
        var penPattern = [UInt8](repeating: 255, count: 8)
        var fillPattern = [UInt8](repeating: 255, count: 8)
    }
    struct TextRun {
        struct Glyph {
            let code: UInt8
            let location: Point
            let bold: Bool
        }
        struct Layout {
            let glyphs: [Glyph]
            let finalPen: Int32
        }
        let location: Point
        let fraction: UInt16
        let bytes: [UInt8]
        let state: State
        var text: String { MacRoman.decode(bytes) }

        /// Exact-size integral font advances, with the source screen font's
        /// one-pixel bold overstrike/advance. The caller resolves the verified
        /// strike; unsupported fractional or scaled metrics cannot be guessed.
        func layout(advances: [Int], ascent: Int) throws -> Layout {
            guard advances.count == 256, advances.allSatisfy({ (0...512).contains($0) }),
                  (0...512).contains(ascent), state.face <= 1,
                  state.numerator == state.denominator, !state.glyphs.fractionalWidths else {
                throw Failure.invalid("unsupported text metrics or scaling")
            }
            let bold = state.face == 1, extraWidth = bold ? 1 : 0
            var pen = Int32(truncatingIfNeeded: location.x * 65536 + Int(fraction))
            // QuickDraw CalcCharExtra: 4.12 per-point value × requested size.
            let characterExtra = Int32(state.characterExtra) * 16 * Int32(state.size)
            var glyphs: [Glyph] = []; glyphs.reserveCapacity(bytes.count)
            for code in bytes {
                glyphs.append(Glyph(code: code, location: Point(x: Int(pen >> 16), y: location.y - ascent), bold: bold))
                pen = pen &+ Int32((advances[Int(code)] + extraWidth) * 65536)
                pen = pen &+ (code == 32 ? state.spaceExtra : characterExtra)
            }
            return Layout(glyphs: glyphs, finalPen: pen)
        }
    }
    enum Shape { case rectangle, oval }
    enum Verb: Int { case frame = 0, paint, erase, invert, fill }
    struct Bitmap {
        let bounds: QuickDrawRect
        let source: QuickDrawRect
        let destination: QuickDrawRect
        let mask: Region?
        let pixelSize: Int
        /// Preserve numeric indices: QuickDraw's indexed shrink operation picks
        /// the greatest index in a source group, not the brightest RGB color.
        let indices: [UInt8]
        /// Unscaled RGBA pixels for the complete bitmap bounds, excluding row padding.
        let pixels: [UInt8]
    }
    enum Operation {
        case text(TextRun)
        case shape(Shape, Verb, QuickDrawRect, State)
        case line(Point, Point, State)
        case bitmap(Bitmap, State)
        case comment(UInt16, Data)
    }
    struct Record {
        let offset: Int
        let opcode: UInt16
        let length: Int
    }
    let frame: QuickDrawRect
    let records: [Record]
    let operations: [Operation]
    let fontNames: [Int: String]
    var textRuns: [TextRun] {
        operations.compactMap { if case .text(let run) = $0 { return run }; return nil }
    }

    init(data: Data) throws {
        guard data.count >= 16, data.count <= 4 * 1024 * 1024 else { throw Failure.invalid("picture length") }
        var cursor = Cursor(source: ByteSource(data))
        let declared = try cursor.word()
        let frame = try cursor.rect()
        guard (declared == 0 || declared == UInt16(truncatingIfNeeded: data.count)),
              frame.width > 0, frame.height > 0, frame.width <= 4096, frame.height <= 4096,
              try cursor.word() == 0x11, try cursor.word() == 0x2ff else {
            throw Failure.invalid("picture header or version")
        }
        var clipData = Data(); clipData.appendU16(10); clipData.append(data.subdata(in: 2..<10))
        var state = try State(clip: Region(data: clipData))
        var records: [Record] = [], operations: [Operation] = [], fontNames: [Int: String] = [:]
        var textLocation = Point.zero, lineLocation = Point.zero, fraction: UInt16 = 0x8000
        var lastRect: QuickDrawRect?, ended = false
        var bitmapBytes = 0
        while cursor.offset < data.count {
            guard records.count < 65536 else { throw Failure.invalid("excessive picture operations") }
            if cursor.offset % 2 != 0 { _ = try cursor.byte() }
            let start = cursor.offset, opcode = try cursor.word()
            switch opcode {
            case 0: break
            case 1: state.clip = try cursor.region()
            case 3:
                state.font = try cursor.signed()
                guard state.font >= 0 else { throw Failure.invalid("font ID") }
            case 4:
                state.face = try cursor.byte()
                guard state.face < 128 else { throw Failure.invalid("font style") }
            case 5: state.textMode = try cursor.word()
            case 6: state.spaceExtra = Int32(bitPattern: try cursor.long())
            case 7:
                state.penSize = try cursor.point()
                guard (0...512).contains(state.penSize.x), (0...512).contains(state.penSize.y) else {
                    throw Failure.invalid("pen dimensions")
                }
            case 8: state.penMode = try cursor.word()
            case 9: state.penPattern = Array(try cursor.take(8))
            case 10: state.fillPattern = Array(try cursor.take(8))
            case 12:
                let dx = try cursor.signed(), dy = try cursor.signed()
                state.origin = state.origin.adding(Point(x: dx, y: dy))
            case 13:
                state.size = try cursor.signed()
                guard (1...512).contains(state.size) else { throw Failure.invalid("font size") }
            case 16:
                state.numerator = try cursor.point(); state.denominator = try cursor.point()
                guard state.numerator.x > 0, state.numerator.y > 0,
                      state.denominator.x > 0, state.denominator.y > 0 else { throw Failure.invalid("text ratio") }
            case 0x15: fraction = try cursor.word()
            case 0x16: state.characterExtra = Int16(try cursor.signed())
            case 0x1a: state.foreground = try cursor.color()
            case 0x1b: state.background = try cursor.color()
            case 0x1e: break // DefHilite has no effect on this document's source-copy drawing.
            case 0x20, 0x21, 0x22, 0x23:
                if opcode == 0x20 || opcode == 0x22 { lineLocation = try cursor.point() }
                let end: Point
                if opcode == 0x20 || opcode == 0x21 { end = try cursor.point() }
                else {
                    let dx = Int(Int8(bitPattern: try cursor.byte())), dy = Int(Int8(bitPattern: try cursor.byte()))
                    end = lineLocation.adding(Point(x: dx, y: dy))
                }
                operations.append(.line(lineLocation, end, state)); lineLocation = end
            case 0x28...0x2b:
                if opcode == 0x28 { textLocation = try cursor.point() }
                else {
                    let dx = opcode == 0x29 || opcode == 0x2b ? Int(try cursor.byte()) : 0
                    let dy = opcode == 0x2a || opcode == 0x2b ? Int(try cursor.byte()) : 0
                    textLocation = textLocation.adding(Point(x: dx, y: dy))
                }
                let length = Int(try cursor.byte()), bytes = Array(try cursor.take(length))
                operations.append(.text(TextRun(location: textLocation, fraction: fraction, bytes: bytes, state: state)))
                fraction = 0x8000 // Pictures TEXTOP resets NEWHFRAC after consuming it.
            case 0x2c:
                let length = Int(try cursor.word()), id = try cursor.signed(), nameLength = Int(try cursor.byte())
                guard id >= 0, nameLength > 0, length == 3 + nameLength else { throw Failure.invalid("font name record") }
                let name = MacRoman.decode(try cursor.take(nameLength))
                guard fontNames[id] == nil || fontNames[id] == name else { throw Failure.invalid("conflicting font names") }
                fontNames[id] = name
            case 0x2e:
                guard try cursor.word() == 4 else { throw Failure.invalid("glyph state length") }
                let flags = Array(try cursor.take(4))
                guard flags.allSatisfy({ $0 <= 1 }) else { throw Failure.invalid("glyph state flags") }
                state.glyphs = GlyphState(outlinePreferred: flags[0] != 0, preserveGlyph: flags[1] != 0,
                    fractionalWidths: flags[2] != 0, scalingDisabled: flags[3] != 0)
            case 0x30...0x34, 0x38...0x3c, 0x50...0x54, 0x58...0x5c:
                let verb = Verb(rawValue: Int(opcode & 7))!
                if opcode & 8 == 0 {
                    let rect = try cursor.rect()
                    guard rect.width >= 0, rect.height >= 0 else { throw Failure.invalid("shape rectangle") }
                    lastRect = rect
                }
                guard let rect = lastRect else { throw Failure.invalid("shape repeats an absent rectangle") }
                operations.append(.shape(opcode < 0x50 ? .rectangle : .oval, verb, rect, state))
            case 0x90, 0x91, 0x98, 0x99:
                operations.append(.bitmap(try cursor.bitmap(opcode: opcode, state: state,
                                                           retainedBytes: &bitmapBytes), state))
            case 0xa0: operations.append(.comment(try cursor.word(), Data()))
            case 0xa1:
                let kind = try cursor.word(), size = Int(try cursor.word())
                operations.append(.comment(kind, try cursor.take(size)))
            case 0xc00:
                let header = try cursor.take(24)
                guard header.prefix(4).allSatisfy({ $0 == 255 }) else { throw Failure.invalid("unsupported resolution header") }
            case 0xff: ended = true
            default: throw Failure.invalid("unsupported opcode \(String(opcode, radix: 16)) at \(start)")
            }
            records.append(Record(offset: start, opcode: opcode, length: cursor.offset - start))
            if ended { break }
        }
        guard ended, cursor.offset == data.count else { throw Failure.invalid("picture end marker") }
        self.frame = frame
        self.records = records
        self.operations = operations
        self.fontNames = fontNames
    }

    private struct Cursor {
        let source: ByteSource
        var offset = 0
        var regionSpans = 0
        mutating func byte() throws -> UInt8 { defer { offset += 1 }; return try source.byte(offset) }
        mutating func word() throws -> UInt16 { defer { offset += 2 }; return try source.u16(offset) }
        mutating func signed() throws -> Int { Int(Int16(bitPattern: try word())) }
        mutating func long() throws -> UInt32 { defer { offset += 4 }; return try source.u32(offset) }
        mutating func rect() throws -> QuickDrawRect { defer { offset += 8 }; return try source.rect(offset) }
        mutating func point() throws -> Point {
            let y = try signed(), x = try signed(); return Point(x: x, y: y)
        }
        mutating func color() throws -> Color { try Color(red: word(), green: word(), blue: word()) }
        mutating func take(_ count: Int) throws -> Data {
            try source.requireUnpack(offset, count)
            defer { offset += count }; return Data(source.slice(offset, offset + count))
        }
        mutating func region() throws -> Region {
            let size = Int(try source.u16(offset)), value = try Region(data: take(size))
            regionSpans += value.bands.reduce(0) { $0 + $1.spans.count }
            guard regionSpans <= 65536 else { throw Failure.invalid("excessive retained region complexity") }
            return value
        }

        mutating func bitmap(opcode: UInt16, state: State, retainedBytes: inout Int) throws -> Bitmap {
            let flags = try word(), rowBytes = Int(flags & 0x3fff), bounds = try rect()
            let indexed = flags & 0x8000 != 0
            guard flags & 0x4000 == 0, rowBytes > 0,
                  bounds.width > 0, bounds.height > 0, bounds.width <= 4096, bounds.height <= 4096,
                  bounds.width <= rowBytes * (indexed ? 1 : 8), rowBytes * bounds.height <= 16 * 1024 * 1024,
                  bounds.width * bounds.height * 4 <= 16 * 1024 * 1024 else {
                throw Failure.invalid("bitmap dimensions")
            }
            let byteCount = bounds.width * bounds.height * 4
            let storage = byteCount + bounds.width * bounds.height
            guard retainedBytes + storage <= 64 * 1024 * 1024 else {
                throw Failure.invalid("excessive bitmap storage")
            }
            var palette: [Int: Color] = [:], packType = 0
            if indexed {
                let version = try word(); packType = Int(try word())
                _ = try long() // Packed size is unused for the row-based formats.
                let horizontalResolution = try long(), verticalResolution = try long()
                let pixelType = try word(), pixelSize = try word(), components = try word(), componentSize = try word()
                let planeBytes = try long(); _ = try long(); _ = try long() // In-memory table pointer/reserved.
                guard version == 0, packType == 0 || packType == 1,
                      horizontalResolution > 0, verticalResolution > 0,
                      pixelType == 0, pixelSize == 8, components == 1, componentSize == 8, planeBytes == 0 else {
                    throw Failure.invalid("unsupported bitmap format")
                }
                _ = try long() // Color table seed is an in-memory identity, not a pixel value.
                let tableFlags = try word(), lastEntry = Int(try word())
                guard tableFlags == 0 || tableFlags == 0x8000, lastEntry <= 255 else {
                    throw Failure.invalid("bitmap color table")
                }
                for index in 0...lastEntry {
                    let value = Int(try word()), color = try color()
                    let key = tableFlags == 0x8000 ? index : value
                    guard key <= 255, palette[key] == nil else { throw Failure.invalid("bitmap palette index") }
                    palette[key] = color
                }
            } else {
                palette = [0: state.background, 1: state.foreground]
            }
            let sourceRect = try rect(), destination = try rect(), mode = try word()
            guard sourceRect.width > 0, sourceRect.height > 0,
                  sourceRect.top >= bounds.top, sourceRect.left >= bounds.left,
                  sourceRect.bottom <= bounds.bottom, sourceRect.right <= bounds.right,
                  destination.width > 0, destination.height > 0, mode == 0 else {
                throw Failure.invalid("bitmap source, destination or transfer mode")
            }
            let mask = opcode == 0x91 || opcode == 0x99 ? try region() : nil
            var pixels: [UInt8] = []; pixels.reserveCapacity(byteCount)
            var indices: [UInt8] = []; indices.reserveCapacity(bounds.width * bounds.height)
            let packed = (opcode == 0x98 || opcode == 0x99) && rowBytes >= 8 && packType != 1
            for _ in 0..<bounds.height {
                let row: [UInt8]
                if packed {
                    let count = rowBytes > 250 ? Int(try word()) : Int(try byte())
                    let decoded = try PICTDecoder.unpackPackBitsRow(source, offset: offset, byteCount: count, rowBytes: rowBytes)
                    row = decoded.row; offset = decoded.next
                } else { row = Array(try take(rowBytes)) }
                for x in 0..<bounds.width {
                    let index = indexed ? Int(row[x]) : Int((row[x / 8] >> (7 - x % 8)) & 1)
                    guard let color = palette[index] else { throw Failure.invalid("unmapped bitmap color") }
                    indices.append(UInt8(index))
                    pixels.append(contentsOf: [UInt8(color.red >> 8), UInt8(color.green >> 8), UInt8(color.blue >> 8), 255])
                }
            }
            retainedBytes += storage
            return Bitmap(bounds: bounds, source: sourceRect, destination: destination, mask: mask,
                          pixelSize: indexed ? 8 : 1, indices: indices, pixels: pixels)
        }
    }

    /// Color QuickDraw stores changes to the preceding scanline, not a list of
    /// independent filled rows. Each pair of coordinates inverts that interval.
    /// SeekRgn/INVPAIR in the original QuickDraw sources defines this behavior.
    struct Region: Equatable {
        struct Band: Equatable {
            let top: Int
            let bottom: Int
            let spans: [Range<Int>]
        }
        let bounds: QuickDrawRect
        let bands: [Band]

        init(data: Data) throws {
            guard data.count >= 10, data.count <= 65534, data.count % 2 == 0 else {
                throw Failure.invalid("region length")
            }
            let reader = ByteSource(data)
            guard Int(try reader.u16(0)) == data.count else { throw Failure.invalid("region boundary") }
            let bounds = try reader.rect(2)
            guard bounds.width >= 0, bounds.height >= 0 else { throw Failure.invalid("region bounds") }
            if data.count == 10 {
                self.bounds = bounds
                self.bands = bounds.width == 0 || bounds.height == 0 ? [] : [
                    Band(top: bounds.top, bottom: bounds.bottom, spans: [bounds.left..<bounds.right])]
                return
            }
            guard bounds.width > 0, bounds.height > 0 else { throw Failure.invalid("empty complex region") }
            var offset = 10, previousY: Int?, endpoints = Set<Int>()
            var bands: [Band] = [], spanCount = 0, ended = false
            while offset < reader.count {
                let y = Int(try reader.i16(offset)); offset += 2
                if y == 32767 { ended = true; break }
                guard y >= bounds.top, y <= bounds.bottom,
                      previousY.map({ y > $0 }) ?? (y == bounds.top) else {
                    throw Failure.invalid("region vertical order")
                }
                if let previousY, !endpoints.isEmpty {
                    let sorted = endpoints.sorted()
                    guard sorted.count % 2 == 0 else { throw Failure.invalid("open region scanline") }
                    spanCount += sorted.count / 2
                    guard spanCount <= 65536 else { throw Failure.invalid("excessive region complexity") }
                    let spans = stride(from: 0, to: sorted.count, by: 2).map { sorted[$0]..<sorted[$0 + 1] }
                    bands.append(Band(top: previousY, bottom: y, spans: spans))
                }
                var previousX: Int?, count = 0, rowEnded = false
                while offset < reader.count {
                    let x = Int(try reader.i16(offset)); offset += 2
                    if x == 32767 { rowEnded = true; break }
                    guard x >= bounds.left, x <= bounds.right, previousX.map({ x > $0 }) ?? true else {
                        throw Failure.invalid("region horizontal order")
                    }
                    if !endpoints.insert(x).inserted { endpoints.remove(x) }
                    previousX = x
                    count += 1
                }
                guard rowEnded, count > 0, count % 2 == 0 else { throw Failure.invalid("region inversion pairs") }
                previousY = y
            }
            guard ended, offset == reader.count, previousY == bounds.bottom,
                  endpoints.isEmpty, !bands.isEmpty else { throw Failure.invalid("unclosed region") }
            self.bounds = bounds
            self.bands = bands
        }

        func contains(x: Int, y: Int) -> Bool {
            guard x >= bounds.left, x < bounds.right, y >= bounds.top, y < bounds.bottom else { return false }
            var lower = 0, upper = bands.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if bands[middle].bottom <= y { lower = middle + 1 } else { upper = middle }
            }
            guard lower < bands.count, bands[lower].top <= y else { return false }
            return bands[lower].spans.contains { $0.contains(x) }
        }
    }
}
