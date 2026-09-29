/// Standard enabled Roman CDEF0 push buttons on Color QuickDraw. All geometry
/// is integer pixel geometry; colors are table roles, not display CLUT indices.
enum OriginalSystemPushButtonRules {
    struct Rect: Equatable {
        var x: Int; var y: Int; var width: Int; var height: Int
        func inset(_ n: Int) -> Rect { .init(x:x+n,y:y+n,width:width-2*n,height:height-2*n) }
    }
    struct Span: Equatable { var x: Int; var y: Int; var width: Int }
    struct LabelOrigin: Equatable { var x: Int; var y: Int }
    struct Colors: Equatable {
        var bodyEntry: Int
        var labelEntry: Int
        var frameEntry: Int
    }
    /// CDEF0:0166–017c,029e–02c8,0302–0308. This is NOT RGB inversion.
    static func colors(pressed: Bool) -> Colors {
        .init(bodyEntry:pressed ? 2 : 1,labelEntry:pressed ? 1 : 2,frameEntry:0)
    }
    /// CDEF0:0204–021c and025c–0268. All lines use their own measured width.
    /// `y` is bitmap ink-atlas origin (baseline minus font ascent).
    static func labelOrigins(width: Int, height: Int, lineWidths: [Int],
                             ascent: Int = 12, descent: Int = 3, leading: Int = 1) -> [LabelOrigin] {
        let lineHeight = ascent+descent+leading
        let lastBaseline = height - ((height-lineWidths.count*lineHeight) >> 1) - leading - descent
        return lineWidths.enumerated().map { index,lineWidth in
            .init(x:(width-lineWidth) >> 1,y:lastBaseline-(lineWidths.count-1-index)*lineHeight-ascent)
        }
    }

    /// Square-corner-oval specialization of System7 ptch32 DrawArc. Source
    /// InitOval b86e and BumpOval b918 use16.16 edges with right-edge bias+1/2.
    /// Middle scanlines do NOT advance oval state (b42c–b448,b60c–b640).
    /// Supports the ordinary button/default-ring dimensions, not arbitrary
    /// non-square oval clamping from a too-small caller rectangle.
    static func filledRoundRect(_ rect: Rect, ovalDiameter: Int) -> [Span] {
        guard rect.width > 0 && rect.height > 0 else { return [] }
        let diameter = max(0,ovalDiameter)
        precondition(diameter <= min(rect.width,rect.height) && diameter <= 64)
        if diameter == 0 {
            return (0..<rect.height).map { .init(x:rect.x,y:rect.y+$0,width:rect.width) }
        }
        var left = diameter*32768
        var right = (rect.width*65536)-diameter*32768+32768
        var ovalY = 1-diameter
        var radiusSquaredMinusYSquared = 2*diameter-1
        var square = 0, odd = 1
        let skipTop = diameter >> 1
        let skipBottom = skipTop+rect.height-diameter
        var result: [Span] = []
        for row in 0..<rect.height {
            if row < skipTop || row >= skipBottom {
                while square < radiusSquaredMinusYSquared {
                    right += 32768; left -= 32768
                    square += odd; odd += 2
                }
                while square > radiusSquaredMinusYSquared {
                    right -= 32768; left += 32768
                    odd -= 2; square -= odd
                }
                radiusSquaredMinusYSquared -= 4*(ovalY+1)
                ovalY += 2
            }
            let first = left >> 16, end = right >> 16
            if end > first { result.append(.init(x:rect.x+first,y:rect.y+row,width:end-first)) }
        }
        return result
    }

    /// ptch32:b458–b496 initializes a second oval inset by PenSize, with
    /// ovalDiameter reduced by twice that size. Frame=outer minus inner.
    static func frameRoundRect(_ rect: Rect, ovalDiameter: Int, penSize: Int) -> [Span] {
        precondition(penSize > 0)
        let outer = filledRoundRect(rect,ovalDiameter:ovalDiameter)
        let innerRect = rect.inset(penSize)
        guard innerRect.width > 0 && innerRect.height > 0 else { return outer }
        let inner = Dictionary(uniqueKeysWithValues: filledRoundRect(innerRect,ovalDiameter:max(0,ovalDiameter-2*penSize)).map { ($0.y,$0) })
        var result: [Span] = []
        for span in outer {
            guard let hole = inner[span.y] else { result.append(span); continue }
            if hole.x > span.x { result.append(.init(x:span.x,y:span.y,width:hole.x-span.x)) }
            let right = hole.x+hole.width, end = span.x+span.width
            if end > right { result.append(.init(x:right,y:span.y,width:end-right)) }
        }
        return result
    }
    static func body(width: Int,height: Int) -> [Span] {
        filledRoundRect(.init(x:0,y:0,width:width,height:height),ovalDiameter:height/2)
    }
    static func outline(width: Int,height: Int) -> [Span] {
        frameRoundRect(.init(x:0,y:0,width:width,height:height),ovalDiameter:height/2,penSize:1)
    }
    /// CODE5:3232–3250: outset4, PenSize3×3, FrameRoundRect oval16×16.
    static func defaultRing(width: Int,height: Int) -> [Span] {
        frameRoundRect(.init(x:-4,y:-4,width:width+8,height:height+8),ovalDiameter:16,penSize:3)
    }
}
