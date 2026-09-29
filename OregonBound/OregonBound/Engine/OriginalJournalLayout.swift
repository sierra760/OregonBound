import Foundation

/// Literal CODE14:307e–3202 record wrapping and0bc0–0cc6 viewport placement.
/// Supplied widths must be measured in the original WTTimes12 face. This helper
/// returns byte-exact DrawText fragments, not modern word-wrapping approximations.
enum OriginalJournalLayout {
    static let contentWidth = 247
    static let contentHeight = 102
    static let visibleLines = 8
    static let visibleLineCount = visibleLines
    static let lineHeight = 12
    static let firstGlyphTop = 3
    static let ascent = 9
    static let firstBaseline = firstGlyphTop + ascent
    static let rootX = 64
    static let rootY = 211

    enum LayoutError: Error, Equatable {
        case unsupportedPascalText
        case invalidMeasurements
        case originalWordBreakUnderflow
        case originalByteCursorWrap
        case truncationBeforeLineStart
    }
    struct Fragment: Equatable, Sendable {
        /// Half-open indices relative to Pascal length byte at0 (text starts1).
        let pascalStart: Int
        let pascalEnd: Int
        let bytes: Data
        let x: Int
        var text: String { String(data: bytes, encoding: .macOSRoman)! }
        /// CR remains in DrawText bytes but WTTimes gives it no ink/advance.
        /// Remove it before BitmapFont.layout, which otherwise treats it as a newline.
        var drawingText: String { text.replacingOccurrences(of: "\r", with: "") }
    }
    struct RecordLayout: Equatable, Sendable {
        /// Includes the length byte and the original fourth-line storage mutation.
        let pascalBytes: Data
        let fragments: [Fragment]
        let wasTruncated: Bool
        let fontResource: Int
    }
    struct PositionedFragment: Equatable, Sendable {
        let recordIndex: Int
        let lineInRecord: Int
        let globalLine: Int
        let fragment: Fragment
        let fontResource: Int
        let x: Int
        let baselineY: Int
        let glyphTopY: Int
    }

    static func layout(text: String, isBold: Bool = false, prefixWidths: [Int],
                       contentWidth: Int = Self.contentWidth) throws -> RecordLayout {
        guard let encoded = text.data(using: .macOSRoman), encoded.count <= 255 else { throw LayoutError.unsupportedPascalText }
        guard prefixWidths.count == encoded.count + 1, prefixWidths.first == 0,
              prefixWidths.allSatisfy({ (0...32767).contains($0) }),
              zip(prefixWidths, prefixWidths.dropFirst()).allSatisfy({ $0 <= $1 }),
              (22...32767).contains(contentWidth) else { throw LayoutError.invalidMeasurements }
        let original = [UInt8(encoded.count)] + Array(encoded)
        var stored = original
        let length = encoded.count
        var cursor = 1
        var boundaries = [1]
        let available = contentWidth - 6
        var threshold = available
        var truncated = false
        while cursor <= length && boundaries.count <= 4 {
            let start = cursor
            while cursor <= length && prefixWidths[cursor] < threshold && original[cursor] != 13 {
                guard cursor < 255 else { throw LayoutError.originalByteCursorWrap }
                cursor += 1
            }
            if cursor <= length {
                if original[cursor] != 13 {
                    while cursor >= start && original[cursor] != 32 { cursor -= 1 }
                    guard cursor >= start else { throw LayoutError.originalWordBreakUnderflow }
                }
                guard cursor < 255 else { throw LayoutError.originalByteCursorWrap }
                cursor += 1
            }
            if boundaries.count == 4 && prefixWidths[length] >= threshold {
                cursor = length
                while prefixWidths[cursor] > threshold { cursor -= 1 }
                cursor -= 3
                guard cursor >= start else { throw LayoutError.truncationBeforeLineStart }
                // 31a6 writes length=cursor;1bfa appendsC9 while preservingD7.
                // 31c4 consequently stores *cursor*, not the new length+1.
                stored = [UInt8(cursor + 1)] + Array(original[1...cursor]) + [0xc9]
                truncated = true
            }
            boundaries.append(cursor)
            if cursor <= length {
                threshold = prefixWidths[cursor] + available - 15
                guard threshold <= 32767 else { throw LayoutError.invalidMeasurements }
            }
        }
        var fragments: [Fragment] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index], end = boundaries[index + 1]
            guard start <= end, end <= stored.count else { throw LayoutError.truncationBeforeLineStart }
            fragments.append(.init(pascalStart: start, pascalEnd: end,
                                   bytes: Data(stored[start..<end]), x: index == 0 ? 3 : 15))
        }
        return RecordLayout(pascalBytes: Data(stored), fragments: fragments,
                            wasTruncated: truncated, fontResource: isBold ? 17847 : 23522)
    }

    /// Full snapshot of the original eight-line viewport. Coordinates are local
    /// to the247×102 text item; add(rootX,rootY) for full-window coordinates.
    static func viewport(records: [RecordLayout], firstLine: Int) -> [PositionedFragment] {
        let count = records.reduce(0) { $0 + $1.fragments.count }
        let first = min(max(0, firstLine), max(0, count - visibleLineCount))
        var global = 0
        var output: [PositionedFragment] = []
        for (recordIndex, record) in records.enumerated() {
            for (lineInRecord, fragment) in record.fragments.enumerated() {
                if (first..<(first + visibleLineCount)).contains(global) {
                    let baseline = firstBaseline + (global - first) * lineHeight
                    output.append(.init(recordIndex: recordIndex, lineInRecord: lineInRecord, globalLine: global,
                        fragment: fragment, fontResource: record.fontResource, x: fragment.x,
                        baselineY: baseline, glyphTopY: baseline - ascent))
                }
                global += 1
            }
        }
        return output
    }
}
