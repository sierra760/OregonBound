/// System 7.0 CDEF 1, variant 0 (Control Manager procID 16).
/// Integer QuickDraw rectangles exclude their bottom/right edges.
enum OriginalClassicScrollBar {
    struct Point: Equatable { var x: Int; var y: Int }
    struct Rect: Equatable {
        var top: Int; var left: Int; var bottom: Int; var right: Int
        var width: Int { right - left }
        var height: Int { bottom - top }
        func contains(_ point: Point) -> Bool {
            point.x >= left && point.x < right && point.y >= top && point.y < bottom
        }
    }
    enum Part: Int { case none = 0, decrease = 20, increase = 21, pageDecrease = 22, pageIncrease = 23, thumb = 129 }
    struct Geometry: Equatable {
        let bounds: Rect
        let thumb: Rect
        let horizontal: Bool
        let thickness: Int
        let travel: Int
        let minimum: Int
        let maximum: Int
        let value: Int
        var axisStart: Int { horizontal ? bounds.left : bounds.top }
        var axisEnd: Int { horizontal ? bounds.right : bounds.bottom }
        var thumbOrigin: Int { horizontal ? thumb.left : thumb.top }
    }

    /// CDEF1:0454 orientation; 058e–05fc fixed-square thumb, cross-axis inset 1.
    static func geometry(bounds: Rect, minimum: Int = 0, maximum: Int, value: Int) -> Geometry {
        let horizontal = bounds.width > bounds.height
        let thickness = horizontal ? bounds.height : bounds.width
        let length = horizontal ? bounds.width : bounds.height
        precondition(thickness > 0 && length >= thickness * 3)
        precondition(minimum <= maximum && maximum - minimum <= 32767)
        let value = min(maximum, max(minimum, value))
        let travel = length - thickness * 3
        let offset = maximum == minimum ? 0 : roundedRatio(travel * (value - minimum), maximum - minimum)
        var thumb = bounds
        if horizontal {
            thumb.left += thickness + offset; thumb.right = thumb.left + thickness
            thumb.top += 1; thumb.bottom -= 1
        } else {
            thumb.top += thickness + offset; thumb.bottom = thumb.top + thickness
            thumb.left += 1; thumb.right -= 1
        }
        return Geometry(bounds: bounds, thumb: thumb, horizontal: horizontal, thickness: thickness,
                        travel: travel, minimum: minimum, maximum: maximum, value: value)
    }

    /// CDEF1:0612–069c. Literal inclusive arrow comparisons occur BEFORE thumb hit testing.
    /// Caller handles control visibility; hilite 254/255 suppresses all CDEF hits.
    static func hitTest(_ point: Point, geometry: Geometry, hilite: UInt8 = 0) -> Part {
        let g = geometry
        guard hilite < 254, g.minimum != g.maximum, g.bounds.contains(point) else { return .none }
        let coordinate = g.horizontal ? point.x : point.y
        if coordinate - g.axisStart <= g.thickness { return .decrease }
        if g.axisEnd - coordinate <= g.thickness { return .increase }
        if g.thumb.contains(point) { return .thumb }
        return coordinate < g.thumbOrigin + g.thickness / 2 ? .pageDecrease : .pageIncrease
    }

    /// CDEF1:0736–0784 position calculation after constrained thumb tracking.
    /// Supply a committed thumb origin, not the pointer coordinate (retain grab offset).
    static func valueForThumbOrigin(_ origin: Int, geometry: Geometry) -> Int {
        let g = geometry
        guard g.travel > 0 else { return g.minimum }
        let offset = min(g.travel, max(0, origin - g.axisStart - g.thickness))
        return g.minimum + roundedRatio((g.maximum - g.minimum) * offset, g.travel)
    }

    /// CDEF1:079c: DIVU remainder strictly greater than floor(divisor/2) rounds up.
    private static func roundedRatio(_ numerator: Int, _ denominator: Int) -> Int {
        numerator / denominator + (numerator % denominator > denominator / 2 ? 1 : 0)
    }
}

/// CODE14 journal viewport/scroll policy. Input counts are WRAPPED rendered lines,
/// including date/header lines, not journal record counts. This models append-only
/// buffers; original cache eviction/reflow is intentionally outside this API.
struct OriginalJournalScrollState: Equatable {
    static let visibleLines = 8
    static let pageLines = 7
    static let followDelayTicks: UInt32 = 900
    static let controlBounds = OriginalClassicScrollBar.Rect(top: -1, left: 247, bottom: 103, right: 263)
    private(set) var totalLines: Int
    private(set) var topLine: Int
    private(set) var lastScrollTick: UInt32
    var maximum: Int { max(0, totalLines - Self.visibleLines) }
    var geometry: OriginalClassicScrollBar.Geometry {
        OriginalClassicScrollBar.geometry(bounds: Self.controlBounds, maximum: maximum, value: topLine)
    }

    init(totalLines: Int = 0, topLine: Int = 0, lastScrollTick: UInt32 = 0) {
        precondition(totalLines >= 0 && totalLines <= 32767)
        self.totalLines = totalLines
        self.topLine = min(max(0, topLine), max(0, totalLines - Self.visibleLines))
        self.lastScrollTick = lastScrollTick
    }

    /// CODE14:11e4 timestamps even an attempted scroll that cannot change value.
    mutating func select(topLine: Int, tick: UInt32) {
        lastScrollTick = tick
        self.topLine = min(maximum, max(0, topLine))
    }

    /// CODE14:03e6–0494; invoke only while original pressed part == current hit part.
    /// Thumb movement is committed separately with select after TrackControl returns.
    mutating func activate(_ part: OriginalClassicScrollBar.Part, tick: UInt32) {
        let delta: Int
        switch part {
        case .decrease: delta = -1
        case .increase: delta = 1
        case .pageDecrease: delta = -Self.pageLines
        case .pageIncrease: delta = Self.pageLines
        case .none, .thumb: return
        }
        select(topLine: topLine + delta, tick: tick)
    }

    /// CODE14:100c–103a / 1174–11a4 / 1554. Already-at-bottom append follows
    /// without resetting lastScrollTick; timeout-follow uses the normal scroll helper.
    mutating func append(totalLines: Int, hasNewRecords: Bool, tick: UInt32) {
        precondition(totalLines >= self.totalLines && totalLines <= 32767)
        let wasAtBottom = topLine == maximum
        self.totalLines = totalLines
        guard hasNewRecords else { return }
        if wasAtBottom {
            topLine = maximum
        } else if tick > lastScrollTick &+ Self.followDelayTicks {
            // Literal unsigned absolute comparison (including its TickCount wrap quirk).
            select(topLine: maximum, tick: tick)
        }
    }
}
