import SwiftUI

/// A Macintosh NFNT bitmap font with its original glyphs and character spacing.
final class BitmapFont {
    struct Metrics: Decodable {
        struct Header: Decodable { let ascent: Int; let descent: Int; let leading: Int; let rect_height: Int }
        struct Glyph: Decodable {
            let index: Int
            let code: Int?
            let missing: Bool
            let atlas_rect: [Int]
            let bearing_x: Int?
            let advance: Int?
        }
        let header: Header
        let glyphs: [Glyph]
        let missing_glyph_index: Int
    }
    struct Placement { let image: CGImage; let rect: CGRect }
    struct Layout { let glyphs: [Placement]; let size: CGSize }
    private static let cache = SessionResourceCache<Int, BitmapFont>()
    private static func cached(_ resource: Int) -> BitmapFont? {
        cache.value(for: resource, session: GameData.sessionID) { BitmapFont(resource: resource) }
    }
    static var bold14: BitmapFont? { cached(16131) }
    static var bold12: BitmapFont? { cached(17847) }
    static var plain12: BitmapFont? { cached(23522) }
    static var plain14: BitmapFont? { cached(22669) }
    // System 7.0 FOND associations; these IDs cannot be derived from size.
    static var chicago12: BitmapFont? { cached(5478) }
    static var geneva9: BitmapFont? { cached(4372) }
    static var geneva12: BitmapFont? { cached(13913) }
    let metrics: Metrics
    private let glyphImages: [Int: CGImage]
    private let glyphIndicesByCode: [Int: Int]
    var lineHeight: Int { metrics.header.ascent + metrics.header.descent + metrics.header.leading }

    init?(resource: Int) {
        guard let url = GameData.url(forResource: "nfnt_\(resource)", withExtension: "json", subdirectory: "fonts"),
              let data = try? Data(contentsOf: url),
              let metrics = try? JSONDecoder().decode(Metrics.self, from: data),
              let png = GameData.url(forResource: "nfnt_\(resource)", withExtension: "png", subdirectory: "fonts"),
              let source = CGImageSourceCreateWithURL(png as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: atlas.width, height: atlas.height, bitsPerComponent: 8,
                                      bytesPerRow: atlas.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(atlas, in: CGRect(x: 0, y: 0, width: atlas.width, height: atlas.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for offset in stride(from: 0, to: atlas.width * atlas.height * 4, by: 4) {
            let ink = bytes[offset]
            bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = ink
        }
        guard let inkAtlas = context.makeImage() else { return nil }
        self.metrics = metrics
        glyphIndicesByCode = Dictionary(uniqueKeysWithValues: metrics.glyphs.compactMap { glyph in
            glyph.code.map { ($0, glyph.index) }
        })
        var images: [Int: CGImage] = [:]
        for glyph in metrics.glyphs where !glyph.missing && glyph.atlas_rect[2] > 0 {
            let r = glyph.atlas_rect
            images[glyph.index] = inkAtlas.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]))
        }
        glyphImages = images
    }

    private func glyph(_ character: Character) -> Metrics.Glyph {
        let bytes = String(character).data(using: .macOSRoman)
        let index = bytes?.count == 1
            ? glyphIndicesByCode[Int(bytes!.first!)] ?? metrics.missing_glyph_index
            : metrics.missing_glyph_index
        let candidate = metrics.glyphs[index]
        return candidate.missing ? metrics.glyphs[metrics.missing_glyph_index] : candidate
    }

    func width(_ text: String) -> Int { text.reduce(0) { $0 + (glyph($1).advance ?? 0) } }

    /// MeasureText positions indexed by original Mac Roman byte boundaries.
    /// Journal layout uses these cumulative advances, not modern word wrapping.
    func prefixWidths(_ text: String) -> [Int]? {
        guard let bytes = text.data(using: .macOSRoman) else { return nil }
        var positions = [0]
        for byte in bytes {
            guard let character = String(data: Data([byte]), encoding: .macOSRoman)?.first else { return nil }
            positions.append(positions.last! + (glyph(character).advance ?? 0))
        }
        return positions
    }

    /// Nil selects safe native wrapping for text from older native saves. Their
    /// LF characters are line breaks; original CODE14 handles CR only, while
    /// BitmapFont.layout handles both. Mixing the two would overlap later rows.
    func journalRecordLayout(_ text: String, isBold: Bool) -> OriginalJournalLayout.RecordLayout? {
        guard !text.contains("\n"), let widths = prefixWidths(text) else { return nil }
        return try? OriginalJournalLayout.layout(text: text, isBold: isBold, prefixWidths: widths)
    }

    func layout(_ text: String, maxWidth: Int = Int.max) -> Layout {
        var placements: [Placement] = []
        var x = 0, y = 0, widest = 0
        let chars = Array(text)
        for i in chars.indices {
            let c = chars[i]
            if c == "\n" || c == "\r" { widest = max(widest, x); x = 0; y += lineHeight; continue }
            // QuickDraw dialog text wraps at spaces. Preserve authored double spaces.
            if c != " " && (i == 0 || chars[i - 1] == " " || chars[i - 1] == "\n") {
                var wordWidth = 0, j = i
                while j < chars.count && chars[j] != " " && chars[j] != "\n" && chars[j] != "\r" {
                    wordWidth += glyph(chars[j]).advance ?? 0; j += 1
                }
                // The original welcome dialog wraps "Oregon" when its advance
                // lands exactly on the right edge (DITL 9220, 419 pixels).
                if x > 0 && x + wordWidth >= maxWidth { widest = max(widest, x); x = 0; y += lineHeight }
            }
            let g = glyph(c)
            if let image = glyphImages[g.index] {
                placements.append(Placement(image: image, rect: CGRect(x: x + (g.bearing_x ?? 0), y: y,
                                                                       width: image.width, height: image.height)))
            }
            x += g.advance ?? 0
        }
        return Layout(glyphs: placements, size: CGSize(width: max(widest, x), height: y + lineHeight))
    }
}

struct OriginalText: View {
    let text: String
    var font: BitmapFont? = .bold14
    var width: Int? = nil
    var body: some View {
        if let font {
            let layout = font.layout(text, maxWidth: width ?? Int.max)
            Canvas { context, _ in
                for glyph in layout.glyphs {
                    context.draw(Image(decorative: glyph.image, scale: 1).interpolation(.none), in: glyph.rect)
                }
            }.frame(width: CGFloat(width ?? Int(layout.size.width)), height: layout.size.height)
                .accessibilityLabel(text)
        } else { Text(text) }
    }
}
