import Foundation

/// Imported text with visible glyph bounds in raster-image coordinates. The
/// reader uses the same crop for caption ink and accessible caption text.
struct CDGuideText {
    /// Font-independent source lines for the substitute-font reading mode.
    /// Caption sheets in this document place each line's baseline inside its
    /// own caption rectangle. Select those lines before displaying their full
    /// text; substitute character widths must not truncate the transcript.
    struct Transcript {
        struct Line { let x: Int; let y: Int; let fontSize: Int; let text: String }
        let lines: [Line]
        init(picture: CDGuidePicture) {
            lines = picture.textRuns.map { run in
                Line(x: run.location.x - run.state.origin.x - picture.frame.left,
                     y: run.location.y - run.state.origin.y - picture.frame.top - 1,
                     fontSize: run.state.size,
                     text: run.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        func text(in crop: QuickDrawRect? = nil) -> String {
            lines.filter { line in
                guard !line.text.isEmpty else { return false }
                guard let crop else { return true }
                return crop.left <= line.x && line.x < crop.right && crop.top <= line.y && line.y < crop.bottom
            }.map(\.text).joined(separator: "\n")
        }
    }
    struct Glyph {
        let code: UInt8
        let bounds: QuickDrawRect
    }
    struct Run { let glyphs: [Glyph] }
    let runs: [Run]

    init(picture: CDGuidePicture, workLimit: Int = 64 * 1024 * 1024,
         fonts: (Int, Int) -> CDGuideRaster.Font?) throws {
        guard (1...64 * 1024 * 1024).contains(workLimit) else {
            throw CDGuidePicture.Failure.invalid("invalid text extraction work limit")
        }
        var work = 0, runs: [Run] = [], loaded: [CDGuideFonts.Key: CDGuideRaster.Font] = [:]
        for run in picture.textRuns {
            let key = CDGuideFonts.Key(family: run.state.font, size: run.state.size)
            let font: CDGuideRaster.Font
            if let existing = loaded[key] { font = existing }
            else {
                guard loaded.count < 32, let resolved = fonts(key.family, key.size) else {
                    throw CDGuidePicture.Failure.invalid("guide text font unavailable")
                }
                try resolved.validate(); loaded[key] = resolved; font = resolved
            }
            let layout = try run.layout(advances: font.advances, ascent: font.ascent)
            var glyphs: [Glyph] = []
            let origin = run.state.origin, frame = picture.frame
            for placement in layout.glyphs {
                let glyph = font.glyphs[Int(placement.code)]
                let space = placement.code == 32
                let width = space ? font.advances[32] : glyph.width
                let height = space ? font.ascent : glyph.height
                let left = placement.location.x + (space ? 0 : glyph.bearingX), top = placement.location.y
                let copies = placement.bold ? 2 : 1
                let cost = width * height * copies
                guard cost <= workLimit - work else { throw CDGuidePicture.Failure.invalid("excessive text extraction work") }
                work += cost
                var minimumX = Int.max, minimumY = Int.max, maximumX = Int.min, maximumY = Int.min
                for y in 0..<height { for x in 0..<width where space || glyph.ink[y * glyph.width + x] != 0 {
                    for overstrike in 0..<copies {
                        let px = left + x + overstrike, py = top + y
                        let localX = px - origin.x - frame.left, localY = py - origin.y - frame.top
                        guard (0..<frame.width).contains(localX), (0..<frame.height).contains(localY),
                              run.state.clip.contains(x: px, y: py) else { continue }
                        minimumX = min(minimumX, localX); minimumY = min(minimumY, localY)
                        maximumX = max(maximumX, localX); maximumY = max(maximumY, localY)
                    }
                } }
                if maximumX >= minimumX {
                    glyphs.append(Glyph(code: placement.code,
                        bounds: QuickDrawRect(top: minimumY, left: minimumX, bottom: maximumY + 1, right: maximumX + 1)))
                }
            }
            if !glyphs.isEmpty { runs.append(Run(glyphs: glyphs)) }
        }
        self.runs = runs
    }

    func text(in crop: QuickDrawRect? = nil) -> String {
        runs.compactMap { run -> String? in
            let bytes = run.glyphs.filter { glyph in
                guard let crop else { return true }
                return glyph.bounds.left < crop.right && glyph.bounds.right > crop.left
                    && glyph.bounds.top < crop.bottom && glyph.bounds.bottom > crop.top
            }.map(\.code)
            let text = MacRoman.decode(bytes).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }
}
