import Foundation

/// CD TEXT200 and its TextEdit style scrap. Offsets address Mac Roman bytes,
/// not Swift characters; CRs and empty lines remain part of the imported text.
struct CDAboutCredits: Equatable {
    struct Run: Equatable {
        let start: Int
        let height: Int
        let ascent: Int
        let font: Int
        let face: UInt8
        let size: Int
        let red: UInt16
        let green: UInt16
        let blue: UInt16
    }
    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self {
            case .invalid(let detail): return "Invalid CD credits: \(detail)"
            }
        }
    }

    // TextEdit uses signed 16-bit text offsets. Check before allocating copies.
    static let maximumTextLength = 32767
    static let maximumStyleLength = 2 + 20 * maximumTextLength
    let bytes: [UInt8]
    let runs: [Run]
    var text: String { MacRoman.decode(bytes) }

    init(text: Data, styles: Data) throws {
        guard text.count <= Self.maximumTextLength,
              styles.count >= 2, styles.count <= Self.maximumStyleLength else {
            throw Failure.invalid("text or style scrap length")
        }
        let reader = BinaryReader(styles)
        let count = Int(try reader.u16(0))
        guard count <= text.count, reader.count == 2 + count * 20,
              text.isEmpty == (count == 0) else {
            throw Failure.invalid("style run count or record length")
        }
        var runs: [Run] = []
        for index in 0..<count {
            let offset = 2 + index * 20
            let start = Int(try reader.u32(offset))
            let height = Int(try reader.i16(offset + 4))
            let ascent = Int(try reader.i16(offset + 6))
            let font = Int(try reader.i16(offset + 8))
            let face = try reader.u8(offset + 10)
            // offset+11 is alignment padding, not another style byte.
            let size = Int(try reader.i16(offset + 12))
            guard start < text.count, index == 0 ? start == 0 : start > runs[index - 1].start,
                  height > 0, ascent >= 0, ascent <= height, font >= 0,
                  face & 0x80 == 0, size > 0 else {
                throw Failure.invalid("style run \(index)")
            }
            runs.append(Run(start: start, height: height, ascent: ascent, font: font, face: face, size: size,
                red: try reader.u16(offset + 14), green: try reader.u16(offset + 16), blue: try reader.u16(offset + 18)))
        }
        bytes = Array(text)
        self.runs = runs
    }

    struct GlyphPlacement: Equatable {
        let byteOffset: Int
        let code: UInt8
        let bold: Bool
        let x: Int
        let y: Int
    }
    struct Layout: Equatable {
        let lineStarts: [Int]
        let textHeight: Int
        let glyphs: [GlyphPlacement]
        var bufferHeight: Int { textHeight + OriginalAboutRules.CreditsScroll.viewportHeight }
    }

    /// The supported CD uses Helvetica12 plain/bold. TEUseStyleScrap applies
    /// font/face/size and asks GetFontInfo for new metrics; its saved height is
    /// not the runtime height. QuickDraw adds one pixel to nonzero bold widths
    /// and overstrikes one pixel right. Roman wrapping uses the full 190px box.
    func layout(advances: [Int], lineHeight: Int, width: Int = 190) throws -> Layout {
        guard advances.count == 256, advances.allSatisfy({ (0...32767).contains($0) }),
              (1...512).contains(lineHeight), runs.allSatisfy({
                  $0.font == 21 && $0.size == 12 && $0.face <= 1 && $0.red == 0 && $0.green == 0 && $0.blue == 0
              }) else { throw Failure.invalid("unsupported credit style or font metrics") }
        var bold = [Bool](); bold.reserveCapacity(bytes.count)
        var prefix = [0], run = 0
        for (offset, byte) in bytes.enumerated() {
            while run + 1 < runs.count && runs[run + 1].start <= offset { run += 1 }
            let styled = runs[run].face == 1, advance = advances[Int(byte)]
            bold.append(styled)
            prefix.append(prefix.last! + advance + (styled && advance != 0 ? 1 : 0))
        }
        let lines = try OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: prefix, width: width)
        let height = lines.lineCount * lineHeight
        guard height <= 32767 - OriginalAboutRules.CreditsScroll.viewportHeight else {
            throw Failure.invalid("credits exceed the original drawing buffer")
        }
        var glyphs: [GlyphPlacement] = []
        for line in 0..<lines.lineCount {
            let start = lines.lineStarts[line], end = lines.lineStarts[line + 1]
            for offset in start..<end where bytes[offset] != 13 {
                glyphs.append(GlyphPlacement(byteOffset: offset, code: bytes[offset], bold: bold[offset],
                    x: prefix[offset] - prefix[start], y: line * lineHeight))
            }
        }
        return Layout(lineStarts: lines.lineStarts, textHeight: height, glyphs: glyphs)
    }

    static func extract(from fork: MacResourceFork, into output: ExtractionOutput) throws {
        let text = try fork.require("TEXT", 200, from: "CD application").data
        let styles = try fork.require("styl", 200, from: "CD application").data
        _ = try Self(text: text, styles: styles)
        try output.write(text, to: "runtime/about_text_200.bin")
        try output.write(styles, to: "runtime/about_styl_200.bin")
    }

    /// Revalidate the raw bytes against the source catalog on every load. No
    /// decoded JSON cache can silently replace the user's original text/style.
    static func load(root: URL, catalog: GameResourceCatalog) throws -> Self {
        func read(_ type: String, path: String, limit: Int) throws -> Data {
            guard let entry = catalog.entries.first(where: {
                $0.role == .cdApplication && $0.type == type && $0.id == 200
            }), entry.disposition == .resource, entry.length >= 0, entry.length <= limit else {
                throw Failure.invalid("missing or oversized \(type)200 source")
            }
            let url = try PreparedResourceFile.url(root: root, path: path)
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == entry.length else {
                throw Failure.invalid("\(type)200 prepared length")
            }
            let data = try Data(contentsOf: url)
            guard data.count == entry.length, SHA256Hex.digest(data) == entry.sha256 else {
                throw Failure.invalid("\(type)200 source fingerprint")
            }
            return data
        }
        return try Self(text: read("TEXT", path: "runtime/about_text_200.bin", limit: maximumTextLength),
                        styles: read("styl", path: "runtime/about_styl_200.bin", limit: maximumStyleLength))
    }

}
