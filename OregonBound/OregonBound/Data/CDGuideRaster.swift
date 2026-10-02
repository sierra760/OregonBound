import Foundation

/// Source-screen drawing rules used by the standalone CD guide. Rasterization
/// stays independent of platform antialiasing and interpolation defaults.
enum CDGuideRaster {
    private static func validateScale(source: Int, destination: Int) throws {
        guard (1...4096).contains(source), (1...4096).contains(destination) else {
            throw CDGuidePicture.Failure.invalid("raster scaling dimensions")
        }
    }

    /// QuickDraw StretchRow uses a truncated 16.16 ratio and carries from a
    /// half-ratio accumulator. A shrinking group preserves its greatest index.
    static func horizontalGroups(source: Int, destination: Int) throws -> [Range<Int>] {
        try validateScale(source: source, destination: destination)
        if source == destination { return (0..<source).map { $0..<($0 + 1) } }
        let ratio = (min(source, destination) * 65536) / max(source, destination)
        var error = ratio / 2, index = 0, groups: [Range<Int>] = []
        groups.reserveCapacity(destination)
        for _ in 0..<destination {
            if source < destination {
                groups.append(index..<min(index + 1, source))
                error += ratio
                if error >= 65536 { error -= 65536; index += 1 }
            } else {
                let start = index
                repeat { index += 1; error += ratio } while error < 65536 && index < source
                error -= 65536
                groups.append(start..<index)
            }
        }
        guard groups.allSatisfy({ !$0.isEmpty && $0.upperBound <= source }) else {
            throw CDGuidePicture.Failure.invalid("raster horizontal sampling")
        }
        return groups
    }

    /// The original vertical DDA uses integer dimensions, including a distinct
    /// initial error for exact shrinking ratios. Zero error reuses the prior row.
    static func verticalGroups(source: Int, destination: Int) throws -> [Range<Int>] {
        try validateScale(source: source, destination: destination)
        var error = -(source > destination && source % destination == 0 ? source - 1 : source / 2)
        var index = 0, group = 0..<0, groups: [Range<Int>] = []
        groups.reserveCapacity(destination)
        for _ in 0..<destination {
            if error < 0 || group.isEmpty {
                let start = index
                repeat { index += 1; error += destination } while error <= 0 && index < source
                group = start..<index
            }
            groups.append(group)
            error -= source
        }
        guard groups.allSatisfy({ !$0.isEmpty && $0.upperBound <= source }) else {
            throw CDGuidePicture.Failure.invalid("raster vertical sampling")
        }
        return groups
    }

    /// Integer scanline edges from QuickDraw's fixed-point oval stepping. Frame
    /// drawing subtracts the same spans for the rectangle inset by the pen size.
    static func ovalSpans(_ rect: QuickDrawRect) throws -> [Range<Int>] {
        guard rect.width >= 0, rect.height >= 0, rect.width <= 4096, rect.height <= 4096 else {
            throw CDGuidePicture.Failure.invalid("raster oval dimensions")
        }
        guard rect.width > 0, rect.height > 0 else { return [] }
        let ratio = Int64(rect.height * 65536 / rect.width)
        let coefficient = ratio * ratio
        var increment = coefficient, square: Int64 = 0
        var radiusSquare = Int64(2 * rect.height - 1), vertical = 1 - rect.height
        var left = Int64(rect.left * 65536 + rect.width * 32768)
        var right = Int64(rect.right * 65536 - rect.width * 32768 + 32768)
        var spans: [Range<Int>] = []; spans.reserveCapacity(rect.height)
        for _ in 0..<rect.height {
            while square >> 32 < radiusSquare {
                left -= 32768; right += 32768
                square += increment; increment += 2 * coefficient
            }
            while square >> 32 > radiusSquare {
                left += 32768; right -= 32768
                increment -= 2 * coefficient; square -= increment
            }
            let start = max(rect.left, min(rect.right, Int(left >> 16)))
            let end = max(start, min(rect.right, Int(right >> 16)))
            spans.append(start..<end)
            radiusSquare -= Int64(4 * (vertical + 1)); vertical += 2
        }
        return spans
    }
    struct Glyph {
        let width: Int
        let height: Int
        let bearingX: Int
        let ink: [UInt8]
    }
    struct Font {
        let advances: [Int]
        let ascent: Int
        let glyphs: [Glyph]

        init(advances: [Int], ascent: Int, glyphs: [Glyph]) {
            self.advances = advances; self.ascent = ascent; self.glyphs = glyphs
        }

        init(strike: BitmapFontExtractor.Strike) throws {
            var glyphs: [Glyph] = [], advances: [Int] = []
            var masks: [Int: Glyph] = [:]
            for code in 0...255 {
                let source = strike.glyph(for: code)
                let glyph: Glyph
                if let cached = masks[source.index] { glyph = cached }
                else {
                    guard source.atlasX >= 0, source.width >= 0, source.width <= 512,
                          strike.atlas.height <= 512, source.atlasX + source.width <= strike.atlas.width else {
                        throw CDGuidePicture.Failure.invalid("guide glyph atlas bounds")
                    }
                    var ink: [UInt8] = []; ink.reserveCapacity(source.width * strike.atlas.height)
                    for y in 0..<strike.atlas.height {
                        let start = y * strike.atlas.width + source.atlasX
                        ink.append(contentsOf: strike.atlas.pixels[start..<(start + source.width)])
                    }
                    glyph = Glyph(width: source.width, height: strike.atlas.height, bearingX: source.bearingX ?? 0, ink: ink)
                    masks[source.index] = glyph
                }
                glyphs.append(glyph); advances.append(source.advance ?? 0)
            }
            self.init(advances: advances, ascent: strike.ascent, glyphs: glyphs)
            try validate()
        }

        fileprivate func validate() throws {
            guard advances.count == 256, glyphs.count == 256, (0...512).contains(ascent),
                  advances.allSatisfy({ (0...512).contains($0) }) else {
                throw CDGuidePicture.Failure.invalid("raster font metrics")
            }
            var storage = 0
            for glyph in glyphs {
                guard (0...512).contains(glyph.width), (0...512).contains(glyph.height),
                      (-512...512).contains(glyph.bearingX), glyph.ink.count == glyph.width * glyph.height,
                      glyph.ink.allSatisfy({ $0 == 0 || $0 == 255 }) else {
                    throw CDGuidePicture.Failure.invalid("raster glyph mask")
                }
                storage += glyph.ink.count
                guard storage <= 4 * 1024 * 1024 else { throw CDGuidePicture.Failure.invalid("excessive glyph storage") }
            }
        }
    }

    /// Unpainted pixels remain transparent so the reader can place the authored
    /// page on its separately imported paper background.
    static func render(_ picture: CDGuidePicture, workLimit: Int = 64 * 1024 * 1024,
                       fonts: (Int, Int) -> Font? = { _, _ in nil }) throws -> PNGEncoder.Image {
        guard (1...64 * 1024 * 1024).contains(workLimit) else {
            throw CDGuidePicture.Failure.invalid("invalid raster work limit")
        }
        var canvas = Canvas(frame: picture.frame, workLimit: workLimit)
        var loadedFonts: [Int: Font] = [:]
        for operation in picture.operations {
            switch operation {
            case .comment: break // Standard screen comment procedure has no drawing effect.
            case .text(let run):
                let key = run.state.font * 1024 + run.state.size
                let font: Font
                if let cached = loadedFonts[key] { font = cached }
                else {
                    guard loadedFonts.count < 32, let resolved = fonts(run.state.font, run.state.size) else {
                        throw CDGuidePicture.Failure.invalid("original guide font unavailable")
                    }
                    try resolved.validate(); loadedFonts[key] = resolved; font = resolved
                }
                guard run.state.textMode == 1 else { throw CDGuidePicture.Failure.invalid("unsupported raster text mode") }
                let layout = try run.layout(advances: font.advances, ascent: font.ascent)
                for placement in layout.glyphs where placement.code != 32 {
                    let glyph = font.glyphs[Int(placement.code)]
                    try canvas.glyph(glyph, at: placement.location, state: run.state)
                    if placement.bold {
                        try canvas.glyph(glyph, at: .init(x: placement.location.x + 1, y: placement.location.y), state: run.state)
                    }
                }
            case .shape(let shape, let verb, let rect, let state):
                try canvas.shape(shape, verb: verb, rect: rect, state: state)
            case .line(let start, let end, let state):
                guard state.penSize.x > 0, state.penSize.y > 0 else { continue }
                guard start.x == end.x || start.y == end.y else {
                    throw CDGuidePicture.Failure.invalid("unsupported diagonal guide line")
                }
                let rect = QuickDrawRect(top: min(start.y, end.y), left: min(start.x, end.x),
                    bottom: max(start.y, end.y) + state.penSize.y, right: max(start.x, end.x) + state.penSize.x)
                try canvas.shape(.rectangle, verb: .paint, rect: rect, state: state)
            case .bitmap(let bitmap, let state): try canvas.bitmap(bitmap, state: state)
            }
        }
        return PNGEncoder.Image(width: picture.frame.width, height: picture.frame.height, colorType: .rgba, pixels: canvas.pixels)
    }

    private struct Canvas {
        let frame: QuickDrawRect
        var pixels: [UInt8]
        let workLimit: Int
        var work = 0
        init(frame: QuickDrawRect, workLimit: Int) {
            self.frame = frame; self.workLimit = workLimit
            pixels = [UInt8](repeating: 0, count: frame.width * frame.height * 4)
        }
        mutating func consume(_ count: Int) throws {
            guard count >= 0, count <= workLimit - work else {
                throw CDGuidePicture.Failure.invalid("excessive raster drawing work")
            }
            work += count
        }
        func visible(_ rect: QuickDrawRect, state: CDGuidePicture.State) -> QuickDrawRect? {
            let left = max(rect.left, state.clip.bounds.left, frame.left + state.origin.x)
            let top = max(rect.top, state.clip.bounds.top, frame.top + state.origin.y)
            let right = min(rect.right, state.clip.bounds.right, frame.right + state.origin.x)
            let bottom = min(rect.bottom, state.clip.bounds.bottom, frame.bottom + state.origin.y)
            guard right > left, bottom > top else { return nil }
            return QuickDrawRect(top: top, left: left, bottom: bottom, right: right)
        }
        mutating func put(x: Int, y: Int, color: CDGuidePicture.Color, state: CDGuidePicture.State) {
            guard state.clip.contains(x: x, y: y) else { return }
            let column = x - frame.left - state.origin.x, row = y - frame.top - state.origin.y
            guard (0..<frame.width).contains(column), (0..<frame.height).contains(row) else { return }
            let offset = (row * frame.width + column) * 4
            pixels[offset] = UInt8(color.red >> 8); pixels[offset + 1] = UInt8(color.green >> 8)
            pixels[offset + 2] = UInt8(color.blue >> 8); pixels[offset + 3] = 255
        }
        mutating func glyph(_ glyph: Glyph, at point: CDGuidePicture.Point, state: CDGuidePicture.State) throws {
            let rect = QuickDrawRect(top: point.y, left: point.x + glyph.bearingX,
                bottom: point.y + glyph.height, right: point.x + glyph.bearingX + glyph.width)
            guard let clipped = visible(rect, state: state) else { return }
            try consume(clipped.width * clipped.height)
            for y in clipped.top..<clipped.bottom { for x in clipped.left..<clipped.right {
                if glyph.ink[(y - rect.top) * glyph.width + x - rect.left] != 0 {
                    put(x: x, y: y, color: state.foreground, state: state)
                }
            } }
        }
        mutating func shape(_ shape: CDGuidePicture.Shape, verb: CDGuidePicture.Verb,
                            rect: QuickDrawRect, state: CDGuidePicture.State) throws {
            guard verb != .invert else { throw CDGuidePicture.Failure.invalid("unsupported background-dependent inversion") }
            if verb == .frame && (state.penSize.x == 0 || state.penSize.y == 0) { return }
            guard (verb != .paint && verb != .frame) || state.penMode == 8 else {
                throw CDGuidePicture.Failure.invalid("unsupported raster pen mode")
            }
            guard let clipped = visible(rect, state: state) else { return }
            try consume(clipped.width * clipped.height)
            let inner = QuickDrawRect(top: rect.top + state.penSize.y, left: rect.left + state.penSize.x,
                bottom: rect.bottom - state.penSize.y, right: rect.right - state.penSize.x)
            let outerSpans = shape == .oval ? try ovalSpans(rect) : []
            let innerSpans = shape == .oval && verb == .frame && inner.width > 0 && inner.height > 0
                ? try ovalSpans(inner) : []
            let pattern = verb == .fill ? state.fillPattern : state.penPattern
            for y in clipped.top..<clipped.bottom { for x in clipped.left..<clipped.right {
                if shape == .oval && !outerSpans[y - rect.top].contains(x) { continue }
                if verb == .frame && y >= inner.top && y < inner.bottom && x >= inner.left && x < inner.right {
                    if shape == .rectangle || (!innerSpans.isEmpty && innerSpans[y - inner.top].contains(x)) { continue }
                }
                let foreground = verb != .erase && pattern[y & 7] & (0x80 >> (x & 7)) != 0
                put(x: x, y: y, color: foreground ? state.foreground : state.background, state: state)
            } }
        }
        mutating func bitmap(_ bitmap: CDGuidePicture.Bitmap, state: CDGuidePicture.State) throws {
            guard let clipped = visible(bitmap.destination, state: state) else { return }
            // Mask misses still visit pixels; account for them before traversal.
            try consume(clipped.width * clipped.height)
            let horizontal = try horizontalGroups(source: bitmap.source.width, destination: bitmap.destination.width)
            let vertical = try verticalGroups(source: bitmap.source.height, destination: bitmap.destination.height)
            for y in clipped.top..<clipped.bottom { for x in clipped.left..<clipped.right {
                if let mask = bitmap.mask, !mask.contains(x: x, y: y) { continue }
                let columns = horizontal[x - bitmap.destination.left], rows = vertical[y - bitmap.destination.top]
                try consume(columns.count * rows.count - 1)
                var selected = -1, selectedIndex = -1
                for sy in rows { for sx in columns {
                    let offset = (bitmap.source.top - bitmap.bounds.top + sy) * bitmap.bounds.width
                        + bitmap.source.left - bitmap.bounds.left + sx
                    let index = Int(bitmap.indices[offset])
                    if index > selectedIndex { selectedIndex = index; selected = offset }
                } }
                guard selected >= 0 else { throw CDGuidePicture.Failure.invalid("empty raster bitmap sample") }
                let offset = selected * 4
                let color = CDGuidePicture.Color(red: UInt16(bitmap.pixels[offset]) * 257,
                    green: UInt16(bitmap.pixels[offset + 1]) * 257, blue: UInt16(bitmap.pixels[offset + 2]) * 257)
                put(x: x, y: y, color: color, state: state)
            } }
        }
    }

}
