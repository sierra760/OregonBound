/// System7 lpch15 TextBox fast path and Roman monostyled TextEdit placement.
/// Full TextEdit clips to its view rectangle; the fast TextBox path does not.
enum OriginalStaticTextLayout {
    struct Line: Equatable {
        let start: Int
        let end: Int
        let x: Int
        let y: Int
    }

    static func lines(bytes: [UInt8], prefixWidths: [Int], width: Int,
                      lineHeight: Int, centered: Bool) throws -> [Line] {
        guard prefixWidths.count == bytes.count + 1, prefixWidths.first == 0,
              width > 0, lineHeight > 0 else {
            throw OriginalTextEditLineLayout.LayoutError.invalidMeasurements
        }
        guard !bytes.isEmpty else { return [] }
        let starts: [Int]
        // lpch15:01a4–01b4. The two-pixel margin belongs only to the
        // fast-path test; full TextEdit wraps at the complete authored width.
        if usesFastPath(bytes: bytes, textWidth: prefixWidths.last!, width: width) {
            starts = [0, bytes.count]
        } else {
            starts = try OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: prefixWidths,
                                                          width: width).lineStarts
        }
        return (0..<starts.count-1).map { row in
            let start = starts[row], end = starts[row+1]
            let advance = prefixWidths[end] - prefixWidths[start]
            // ASR rounds down, including a negative difference for overflow
            // whitespace. Roman centered lines retain their trailing spaces.
            let x = centered ? 1 + ((width - advance - 1) >> 1) : 1
            return Line(start: start, end: end, x: x, y: row * lineHeight)
        }
    }

    static func usesFastPath(bytes: [UInt8], textWidth: Int, width: Int) -> Bool {
        !bytes.contains(13) && textWidth < width - 2
    }

}
