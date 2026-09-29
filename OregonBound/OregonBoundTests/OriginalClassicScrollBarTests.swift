import Testing
@testable import OregonBound

struct OriginalClassicScrollBarTests {
    @Test func originalJournalResourceGeometryAndFixedThumb() {
        let bounds = OriginalJournalScrollState.controlBounds
        let low = OriginalClassicScrollBar.geometry(bounds: bounds, maximum: 100, value: 0)
        let mid = OriginalClassicScrollBar.geometry(bounds: bounds, maximum: 100, value: 50)
        let high = OriginalClassicScrollBar.geometry(bounds: bounds, maximum: 100, value: 100)
        #expect(low.thumb == .init(top: 15, left: 248, bottom: 31, right: 262))
        #expect(mid.thumb.top == 43 && high.thumb.top == 71)
        #expect(high.thumb.height == 16 && high.thumb.width == 14 && high.travel == 56)
        let guide = OriginalClassicScrollBar.geometry(bounds: .init(top: 0, left: 0, bottom: 167, right: 16), maximum: 50, value: 25)
        #expect(guide.thumb.top == 75) // 59.5 rounds DOWN: CDEF1:079c.
    }

    @Test func arrowPrecedenceAndQuickDrawExclusiveEdges() {
        let g = OriginalClassicScrollBar.geometry(bounds: OriginalJournalScrollState.controlBounds, maximum: 100, value: 0)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 15), geometry: g) == .decrease)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 16), geometry: g) == .thumb)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 31), geometry: g) == .pageIncrease)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 87), geometry: g) == .increase)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 263, y: 87), geometry: g) == .none)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 103), geometry: g) == .none)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 16), geometry: g, hilite: 254) == .none)
        let empty = OriginalClassicScrollBar.geometry(bounds: g.bounds, maximum: 0, value: 0)
        #expect(OriginalClassicScrollBar.hitTest(.init(x: 250, y: 0), geometry: empty) == .none)
    }

    @Test func dragCommitAndHorizontalOrientation() {
        let g = OriginalClassicScrollBar.geometry(bounds: .init(top: 0, left: 0, bottom: 16, right: 104), minimum: 10, maximum: 17, value: 10)
        #expect(g.horizontal && g.thumb == .init(top: 1, left: 16, bottom: 15, right: 32))
        #expect(OriginalClassicScrollBar.valueForThumbOrigin(20, geometry: g) == 10) // 0.5 down.
        #expect(OriginalClassicScrollBar.valueForThumbOrigin(21, geometry: g) == 11)
        #expect(OriginalClassicScrollBar.valueForThumbOrigin(-100, geometry: g) == 10)
        #expect(OriginalClassicScrollBar.valueForThumbOrigin(1000, geometry: g) == 17)
    }

    @Test func journalPagesOverlapAndAttemptAtEndStillTimestamps() {
        var state = OriginalJournalScrollState(totalLines: 30)
        state.activate(.pageIncrease, tick: 4)
        #expect(state.topLine == 7 && state.maximum == 22)
        state.activate(.increase, tick: 5)
        #expect(state.topLine == 8)
        state.activate(.pageDecrease, tick: 6)
        #expect(state.topLine == 1)
        state.select(topLine: -99, tick: 7)
        state.activate(.decrease, tick: 8)
        #expect(state.topLine == 0 && state.lastScrollTick == 8)
        state.activate(.thumb, tick: 9)
        #expect(state.lastScrollTick == 8)
    }

    @Test func appendPreservesReadingUntilStrictTimeoutAndNeedsANewRecord() {
        var state = OriginalJournalScrollState(totalLines: 20, topLine: 12, lastScrollTick: 0)
        state.append(totalLines: 21, hasNewRecords: true, tick: 10)
        #expect(state.topLine == 13 && state.lastScrollTick == 0)
        state.select(topLine: 3, tick: 100)
        state.append(totalLines: 22, hasNewRecords: true, tick: 1000)
        #expect(state.topLine == 3)
        state.append(totalLines: 22, hasNewRecords: false, tick: 1001)
        #expect(state.topLine == 3)
        state.append(totalLines: 23, hasNewRecords: true, tick: 1001)
        #expect(state.topLine == 15 && state.lastScrollTick == 1001)
    }

    @Test func originalUnsignedAbsoluteDeadlineWrapIsPreserved() {
        var state = OriginalJournalScrollState(totalLines: 20, topLine: 1, lastScrollTick: UInt32.max - 10)
        state.append(totalLines: 21, hasNewRecords: true, tick: UInt32.max - 9)
        #expect(state.topLine == 13) // Source ADD.L wraps, then BLS compares unsigned.
    }
}
