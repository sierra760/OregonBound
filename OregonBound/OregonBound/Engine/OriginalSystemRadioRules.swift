/// Roman System7 CDEF0, variant2. RGB values are Color QuickDraw requests;
/// this recipe does not simulate a display CLUT. See ORIGINAL_SYSTEM_RADIO.md.
enum OriginalSystemRadioRules {
    struct Rect: Equatable {
        var x: Int; var y: Int; var width: Int; var height: Int
    }
    struct Span: Equatable {
        var x: Int; var y: Int; var width: Int
    }
    enum LabelTreatment: Equatable {
        case normal
        case grayishTextOr // Color GrafPort; CDEF0:02b4–02be.
        case eraseGrayPatternInsideControl // Monochrome GrafPort; 0388–03d6.
    }
    struct State: Equatable {
        var selected: Bool
        var highlight: UInt8 = 0
        var colorGrafPort: Bool = false
        var penSize: Int { highlight > 0 && highlight < 254 ? 2 : 1 }
        var labelTreatment: LabelTreatment {
            highlight < 254 ? .normal : colorGrafPort ? .grayishTextOr : .eraseGrayPatternInsideControl
        }
    }
    static let controlWidth = 75
    static let controlHeight = 15
    static let labelX = 18 // CDEF0:0252–0256.
    static let frameColorEntry = 0
    static let textColorEntry = 2

    /// CDEF0:047c–04be: integer arithmetic shift rounds odd spare space down,
    /// then subtracts from bottom. Thus a15-high control gives marker y2, not1.
    static func markerRect(control: Rect, rightToLeft: Bool = false) -> Rect {
        let bottom = control.y + control.height - ((control.height - 12) >> 1)
        let x = rightToLeft ? control.x + control.width - 14 : control.x + 2
        return .init(x:x,y:bottom-12,width:12,height:12)
    }
    /// CDEF0:0204–021c, plain Chicago12 ascent12/descent3/leading1.
    static func labelBaseline(controlHeight: Int = 15, lineCount: Int = 1,
                              ascent: Int = 12, descent: Int = 3, leading: Int = 1) -> Int {
        let height = lineCount * (ascent + descent + leading)
        return controlHeight - ((controlHeight - height) >> 1) - leading - descent
    }

    /// The square-oval specialization of actual System7 ptch32:b86e/b918.
    /// InitOval uses aspect ratio1, so oddNumber and square have zero fractions.
    /// Edge coordinates remain16.16 fixed point; right is biased by1/2 pixel.
    /// Keeping the incremental loops mirrors BumpOval rather than a geometric
    /// ellipse threshold or platform path rasterizer.
    static func filledCircleSpans(size: Int, x: Int = 0, y: Int = 0) -> [Span] {
        precondition((1...12).contains(size))
        var left = size * 32768
        var right = size * 32768 + 32768
        var ovalY = 1 - size
        var radiusSquaredMinusYSquared = 2 * size - 1
        var square = 0
        var odd = 1
        var result: [Span] = []
        for row in 0..<size {
            while square < radiusSquaredMinusYSquared {
                right += 32768; left -= 32768
                square += odd; odd += 2
            }
            while square > radiusSquaredMinusYSquared {
                right -= 32768; left += 32768
                odd -= 2; square -= odd
            }
            let first = left >> 16, last = right >> 16
            if last > first { result.append(.init(x:x+first,y:y+row,width:last-first)) }
            radiusSquaredMinusYSquared -= 4 * (ovalY + 1)
            ovalY += 2
        }
        return result
    }

    /// DrawArc subtracts the inset inner oval from the outer one for FrameOval;
    /// CDEF0 resets PenNormal before painting the selected dot inset3.
    static func markerSpans(state: State, control: Rect = .init(x:0,y:0,width:75,height:15)) -> [Span] {
        let rect = markerRect(control: control)
        let pen = state.penSize
        let outside = filledCircleSpans(size:12,x:rect.x,y:rect.y)
        let inside = Dictionary(uniqueKeysWithValues: filledCircleSpans(size:12-2*pen,x:rect.x+pen,y:rect.y+pen).map { ($0.y,$0) })
        var pixels = Set<Int>()
        // Fixed12×12 marker-local address; emit merged spans in draw order byrow.
        func add(_ first: Int,_ end: Int,_ row: Int) {
            guard end > first else { return }
            for x in first..<end { pixels.insert((row-rect.y)*12+x-rect.x) }
        }
        for outer in outside {
            if let inner = inside[outer.y] {
                add(outer.x,inner.x,outer.y)
                add(inner.x+inner.width,outer.x+outer.width,outer.y)
            } else { add(outer.x,outer.x+outer.width,outer.y) }
        }
        if state.selected {
            for span in filledCircleSpans(size:6,x:rect.x+3,y:rect.y+3) { add(span.x,span.x+span.width,span.y) }
        }
        var result: [Span] = []
        for y in 0..<12 {
            var x = 0
            while x < 12 {
                if !pixels.contains(y*12+x) { x += 1; continue }
                let first = x
                repeat { x += 1 } while x < 12 && pixels.contains(y*12+x)
                result.append(.init(x:rect.x+first,y:rect.y+y,width:x-first))
            }
        }
        return result
    }
}
