import Foundation

/// The original reader uses the System Chicago outline at ten points when no
/// matching bitmap strike exists. Read its Mac Roman mapping and device widths
/// explicitly: modern font advances differ from these stored screen metrics.
/// This decodes metrics only; the importer separately pins the complete font
/// before its outlines may reach a platform rasterizer.
struct CDGuideOutlineFont {
    static let resourceID = 5466
    static let expectedSHA256 = "d61afc9e98bf41ba4c56c0b47d425f9f4f16a63af541cc8cc90d9e20796a8f6b"
    let pointSize = 10
    let glyphIDs: [UInt16]
    let advances: [Int]

    init(data: Data) throws {
        typealias Failure = CDGuidePicture.Failure
        guard data.count >= 12, data.count <= 4 * 1024 * 1024 else {
            throw Failure.invalid("outline font length")
        }
        let reader = ByteSource(data)
        let count = Int(try reader.u16(4))
        guard try reader.u32(0) == 0x00010000, (1...64).contains(count) else {
            throw Failure.invalid("outline font directory")
        }
        let directoryEnd = 12 + count * 16
        try reader.requireUnpack(0, directoryEnd)
        var tables: [String: Range<Int>] = [:]
        for index in 0..<count {
            let offset = 12 + index * 16
            let name = MacRoman.decode(reader.slice(offset, offset + 4))
            let start = Int(try reader.u32(offset + 8)), length = Int(try reader.u32(offset + 12))
            guard start >= directoryEnd, start % 4 == 0, length > 0, tables[name] == nil else {
                throw Failure.invalid("outline font table location")
            }
            try reader.requireUnpack(start, length)
            let range = start..<(start + length)
            guard !tables.values.contains(where: { $0.overlaps(range) }) else {
                throw Failure.invalid("overlapping outline font tables")
            }
            tables[name] = range
        }
        func table(_ name: String) throws -> ByteSource {
            guard let range = tables[name] else { throw Failure.invalid("missing outline font \(name) table") }
            return ByteSource(Data(reader.slice(range.lowerBound, range.upperBound)))
        }
        let maxp = try table("maxp"), glyphCount = Int(try maxp.u16(4))
        guard try maxp.u32(0) == 0x00010000, (1...4096).contains(glyphCount) else {
            throw Failure.invalid("outline glyph count")
        }
        let cmap = try table("cmap"), mapCount = Int(try cmap.u16(2))
        guard try cmap.u16(0) == 0, (1...64).contains(mapCount) else {
            throw Failure.invalid("outline character map directory")
        }
        let mapDirectoryEnd = 4 + mapCount * 8
        try cmap.requireUnpack(0, mapDirectoryEnd)
        var macRomanOffset: Int?
        for index in 0..<mapCount {
            let entry = 4 + index * 8
            if try cmap.u16(entry) == 1, try cmap.u16(entry + 2) == 0 {
                guard macRomanOffset == nil else { throw Failure.invalid("duplicate Mac Roman character maps") }
                macRomanOffset = Int(try cmap.u32(entry + 4))
            }
        }
        guard let mapOffset = macRomanOffset, mapOffset >= mapDirectoryEnd,
              try cmap.u16(mapOffset) == 6 else { throw Failure.invalid("missing Mac Roman format-six map") }
        let mapLength = Int(try cmap.u16(mapOffset + 2))
        let firstCode = Int(try cmap.u16(mapOffset + 6)), codeCount = Int(try cmap.u16(mapOffset + 8))
        guard firstCode <= 255, codeCount > 0, firstCode + codeCount <= 256,
              mapLength == 10 + codeCount * 2 else { throw Failure.invalid("Mac Roman map bounds") }
        try cmap.requireUnpack(mapOffset, mapLength)
        var glyphIDs = [UInt16](repeating: 0, count: 256)
        for index in 0..<codeCount {
            let id = try cmap.u16(mapOffset + 10 + index * 2)
            guard id < glyphCount else { throw Failure.invalid("Mac Roman glyph index") }
            glyphIDs[firstCode + index] = id
        }
        let hdmx = try table("hdmx"), deviceCount = Int(try hdmx.u16(2)), recordSize = Int(try hdmx.u32(4))
        guard try hdmx.u16(0) == 0, (1...256).contains(deviceCount),
              recordSize == ((glyphCount + 2 + 3) / 4) * 4,
              hdmx.count == 8 + deviceCount * recordSize else { throw Failure.invalid("outline device metrics") }
        var deviceWidths: [Int]?, previousSize = 0
        for index in 0..<deviceCount {
            let offset = 8 + index * recordSize, size = Int(try hdmx.byte(offset))
            guard size > previousSize else { throw Failure.invalid("outline device size order") }
            previousSize = size
            if size == pointSize {
                let maximum = Int(try hdmx.byte(offset + 1))
                let widths = hdmx.slice(offset + 2, offset + 2 + glyphCount).map(Int.init)
                guard widths.allSatisfy({ $0 <= maximum }) else { throw Failure.invalid("outline device width maximum") }
                deviceWidths = widths
            }
        }
        guard let deviceWidths else { throw Failure.invalid("missing ten-point outline device widths") }
        self.glyphIDs = glyphIDs
        self.advances = glyphIDs.map { deviceWidths[Int($0)] }
    }
}
