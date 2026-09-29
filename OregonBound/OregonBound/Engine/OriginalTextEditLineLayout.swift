/// System 7.0 Roman-only, monostyled TextEdit line starts. The password hint
/// probes TEKey on a cloned TERec and accepts its nLines <= 3 (CODE15:033c).
/// Metrics must use the actual font; the original hint uses Chicago 12 plain.
enum OriginalTextEditLineLayout {
    enum LayoutError: Error, Equatable { case invalidMeasurements, nonAdvancingLine }
    struct Layout: Equatable {
        /// Byte offsets, including terminal teLength. Empty text has [0].
        let lineStarts: [Int]
        var lineCount: Int { lineStarts.count - 1 }
    }

    /// prefixWidths[n] is the advance of the first n Mac Roman bytes. Width is
    /// destRect.right-left, with no inset for the caret. CR is the only hard break.
    static func layout(bytes: [UInt8], prefixWidths: [Int], width: Int = 135) throws -> Layout {
        guard bytes.count <= 32767, prefixWidths.count == bytes.count + 1,
              prefixWidths.first == 0, (1...32767).contains(width),
              prefixWidths.allSatisfy({ (0...Int(Int32.max)).contains($0) }),
              zip(prefixWidths, prefixWidths.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw LayoutError.invalidMeasurements
        }
        var starts = [0]
        var start = 0
        while start < bytes.count {
            // ptch27:0aac–0ae4 + lpch15:0846–08cc. A hit occurs at >= width;
            // TE backs off the hit character, including an exact-edge hit.
            var hit = start
            while hit < bytes.count && prefixWidths[hit + 1] - prefixWidths[start] < width {
                hit += 1
            }
            var end: Int
            if let carriageReturn = bytes[start..<hit].firstIndex(of: 13) {
                end = carriageReturn + 1
            } else if hit == bytes.count {
                end = hit
            } else {
                // lpch15:2932 uses TST.B on the absolute byte offset, not TST.W.
                // This quirk matters at multiples of 256 for oversized pasted text.
                var boundary = hit
                if boundary & 255 != 0 {
                    while boundary < bytes.count && bytes[boundary] <= 32 {
                        let isReturn = bytes[boundary] == 13
                        boundary += 1
                        if isReturn { break }
                    }
                }
                if boundary > hit {
                    end = boundary
                } else {
                    // Roman FindWord scans LEFT starting before the hit character.
                    // If the word began on this line, split it at the measured hit.
                    var wordStart = hit
                    while wordStart > 0 && bytes[wordStart - 1] > 32 { wordStart -= 1 }
                    end = wordStart > start ? wordStart : hit
                }
            }
            // The 135px Chicago hint cannot hit this case (widMax=14). Reject
            // unsupported external metrics rather than repeat a zero-length line.
            guard end > start else { throw LayoutError.nonAdvancingLine }
            starts.append(end)
            start = end
        }
        return Layout(lineStarts: starts)
    }
}
