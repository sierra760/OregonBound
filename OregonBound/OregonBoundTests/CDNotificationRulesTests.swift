import Foundation
import CoreGraphics
import Testing
@testable import OregonBound

struct CDNotificationRulesTests {
    @Test func modelRecordsTypedNotificationParametersWithoutChangingJournalOrRNG() {
        var cd = Journey(seed: 17, edition: .macintoshCD12)
        var classic = Journey(seed: 17, edition: .macintosh11)
        for code in [22,26,27,30,33,34,37,38,42,52,63,69] {
            OriginalTrailEvents.record(code, part: .axles, in: &cd)
            if code != 69 { OriginalTrailEvents.record(code, part: .axles, in: &classic) }
        }
        let events = cd.journal.compactMap(\.cdNotification)
        #expect(events == [.init(code:23), .init(code:26,parameter:0), .init(code:26,parameter:1),
            .init(code:47,parameter:4), .init(code:47,parameter:4), .init(code:47,parameter:4),
            .init(code:37,parameter:3), .init(code:37,parameter:4), .init(code:37,parameter:8),
            .init(code:63), .init(code:69)])
        #expect(classic.journal.allSatisfy { $0.cdNotification == nil })
        #expect(cd.randomState == 17 && classic.randomState == 17)
        #expect(cd.journal.count == 12 && classic.journal.count == 11)
        #expect(Array(cd.journal.prefix(11)).map(\.text) == classic.journal.map(\.text))
    }

    @Test func notificationMetadataRoundTripsAndOldEntriesStayAbsent() throws {
        var trip = Journey(seed: 9, edition: .macintoshCD12)
        OriginalTrailEvents.record(27, in: &trip)
        let data = try JSONEncoder().encode(trip)
        let loaded = try JSONDecoder().decode(Journey.self, from: data)
        #expect(loaded.journal.last?.cdNotification == .init(code:26,parameter:1))
        var object = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        var entries = object["journal"] as! [[String:Any]]
        for index in entries.indices { entries[index].removeValue(forKey:"cdNotification") }
        object["journal"] = entries
        let older = try JSONDecoder().decode(Journey.self, from: JSONSerialization.data(withJSONObject:object))
        #expect(older.journal.allSatisfy { $0.cdNotification == nil })
        #expect(older.journal.map(\.text) == trip.journal.map(\.text))
    }

    @Test func paneDeadlineUsesFourDistinctTicksAndLogicalRedrawExtendsIt() {
        var pane = CDNotificationRules.Presentation(openedAt: 100)
        #expect(pane.poll(at: 577) == .none)
        #expect(pane.poll(at: 577) == .none) // Duplicate host callbacks are not source ticks.
        #expect(pane.poll(at: 578) == .none)
        #expect(pane.poll(at: 579) == .none)
        #expect(pane.poll(at: 580) == .expired) // Equality expires, even if covered.
        pane = .init(openedAt: 100)
        #expect(pane.poll(at: 200) == .none)
        #expect(pane.poll(at: 201) == .none)
        pane.redraw(at: 500)
        #expect(pane.poll(at: 979) == .none) // Redraw preserves the partial timer.
        #expect(pane.poll(at: 980) == .expired)
    }

    @Test func paneDoesNotCatchUpAndPreservesUnsignedDeadlineComparison() {
        var pane = CDNotificationRules.Presentation(openedAt: 0)
        #expect(pane.poll(at: 2000) == .none)
        #expect(pane.poll(at: 2001) == .none)
        #expect(pane.poll(at: 2002) == .none)
        #expect(pane.poll(at: 2003) == .expired)
        pane = .init(openedAt: UInt32.max - 20)
        for tick in (UInt32.max - 19)...(UInt32.max - 17) { #expect(pane.poll(at: tick) == .none) }
        // CODE4 uses BCS with its wrapped deadline; do not replace it with elapsed-time arithmetic.
        #expect(pane.poll(at: UInt32.max - 16) == .expired)
    }

    @Test func paletteCyclesTwoIndependentRingsWithoutTouchingReservedIndex() {
        var palette = CDNotificationRules.PaletteCycle()
        #expect(palette.sourceIndex(for: 207) == 207)
        palette.poll(at: 100)
        #expect([207,208,209,210,216,217,225,226].map { palette.sourceIndex(for: $0) }
            == [208,210,209,211,207,218,217,226])
        palette.poll(at: 101)
        #expect(palette.sourceIndex(for: 207) == 208 && palette.sourceIndex(for: 217) == 218)
        palette.poll(at: 102)
        #expect(palette.sourceIndex(for: 207) == 208 && palette.sourceIndex(for: 217) == 219)
        palette.poll(at: 106)
        #expect(palette.sourceIndex(for: 207) == 210 && palette.sourceIndex(for: 217) == 220)
        palette.poll(at: 10000) // One rotation per invocation, never catch up.
        #expect(palette.sourceIndex(for: 207) == 211 && palette.sourceIndex(for: 217) == 221)
    }

    @Test func paletteArtworkKeepsPixelIndicesAndOnlyRewritesAuthoredColors() throws {
        var colors = (0..<256).flatMap { [UInt8($0), UInt8(0), UInt8(0)] }
        let space = try #require(CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: &colors))
        let bytes = Data([207,209,217,42])
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let source = try #require(CGImage(width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: 4, space: space, bitmapInfo: [], provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        var palette = CDNotificationRules.PaletteCycle(); palette.poll(at: 100)
        let output = try #require(CDNotificationArtwork.recolored(source, palette: palette))
        #expect(output.dataProvider?.data as Data? == bytes)
        let table = try #require(output.colorSpace?.colorTable)
        #expect([207,209,217,42].map { table[$0 * 3] } == [208,209,218,42])
        #expect(output.width == 4 && output.height == 1 && output.bitsPerPixel == 8)
    }

    @Test func noticeGuidePageOpensItsTopicInsteadOfTheCurrentLandmark() {
        var guide = OriginalGuide(locationID: "independence", edition: .macintoshCD12, initialPage: 61)
        #expect(guide.page == 61 && guide.selection == 61 && guide.textResource == 3171)
        guide.turn(forward: true)
        #expect(guide.page == 62)
        let ordinary = OriginalGuide(locationID: "independence", edition: .macintoshCD12)
        #expect(ordinary.page == 35)
    }

    @Test func guideCornerHitUsesParentBoundsRatherThanTheIconDrawingBounds() {
        #expect(CDNotificationRules.opensGuide(x: 235, y: 156))
        #expect(CDNotificationRules.opensGuide(x: 261, y: 187))
        #expect(!CDNotificationRules.opensGuide(x: 234, y: 170))
        #expect(!CDNotificationRules.opensGuide(x: 240, y: 188))
        #expect(!CDNotificationRules.opensGuide(x: 267, y: 170))
    }

    private let clear = CDNotificationRules.Context(weather: 0, snow: 0, destination: 5)

    @Test func priorityAndOrdinaryEventsCompeteWithinOneDay() {
        var state = CDNotificationRules.State()
        state.beginBatch()
        state.receive(.init(code: 0), in: clear)
        state.receive(.init(code: 9), in: clear) // Low priority cannot replace fog.
        #expect(state.selected?.art == 0 && state.selected?.sound == 4005)
        state.receive(.init(code: 26, parameter: 0), in: clear)
        state.receive(.init(code: 65), in: clear) // Fire cannot replace a priority injury.
        #expect(state.selected?.art == 18 && state.selected?.priority == true)
        state.receive(.init(code: 24), in: clear) // Later priority wins.
        #expect(state.selected?.art == 25)
        state.beginBatch()
        #expect(state.selected == nil)
        state.receive(.init(code: 65), in: clear)
        #expect(state.selected?.art == 1 && state.selected?.cycle == true)
    }

    @Test func destinationGuardsPersistAcrossBatchesAndUseRawDestination() {
        var state = CDNotificationRules.State()
        let start = CDNotificationRules.Context(weather: 0, snow: 0, destination: 0)
        state.receive(.init(code: 25), in: start)
        #expect(state.selected == nil)
        state.receive(.init(code: 25), in: clear)
        #expect(state.selected?.art == 26)
        state.beginBatch(); state.receive(.init(code: 25), in: clear)
        #expect(state.selected == nil)
        state.receive(.init(code: 25), in: .init(weather: 0, snow: 0, destination: 6))
        #expect(state.selected?.art == 26)
        state.beginBatch(); state.receive(.init(code: 9), in: clear)
        #expect(state.selected?.art == 11) // Independent guard for bad water.
    }

    @Test func foodAidVariantsAdvanceWithinTheBatchWithoutRandomness() {
        var state = CDNotificationRules.State()
        var frames: [Int] = []
        for _ in 0..<8 { state.receive(.init(code: 20), in: clear); frames.append(state.selected!.art) }
        #expect(frames == [28,29,30,31,33,35,28,29])
        state.beginBatch()
        state.receive(.init(code: 20), in: clear)
        #expect(state.selected?.art == 28)
        let snow = CDNotificationRules.Context(weather: 0, snow: 1, destination: 5)
        state.receive(.init(code: 20), in: snow); #expect(state.selected?.art == 32)
        state.receive(.init(code: 20), in: snow); #expect(state.selected?.art == 34)
    }

    @Test func snowboundRetainsLastCandidateSoundEvenWhenThatCandidateLostSelection() {
        var state = CDNotificationRules.State()
        state.receive(.init(code: 12), in: clear)
        #expect(state.selected?.art == 44 && state.selected?.sound == 0)
        state.receive(.init(code: 26), in: clear)
        state.receive(.init(code: 8), in: clear) // Candidate sound4004, rejected by injury priority.
        #expect(state.selected?.art == 18)
        state.beginBatch(); state.receive(.init(code: 12), in: clear)
        #expect(state.selected?.sound == 4004 && state.selected?.external == false)
    }

    @Test func weatherAndParameterVariantsChooseTheirGuideAndSound() {
        var state = CDNotificationRules.State()
        state.receive(.init(code: 26, parameter: 1), in: .init(weather: 2, snow: 0, destination: 5))
        #expect(state.selected?.art == 61)
        state.beginBatch(); state.receive(.init(code: 24), in: .init(weather: 3, snow: 1, destination: 5))
        #expect(state.selected?.art == 22) // Rain wins over snow in this branch.
        state.beginBatch(); state.receive(.init(code: 47, parameter: 5), in: clear)
        #expect(state.selected?.art == 20 && state.selected?.guide == 68 && state.selected?.sound == 4012)
        state.beginBatch(); state.receive(.init(code: 37, parameter: 6), in: clear)
        #expect(state.selected?.art == 60 && state.selected?.guide == 45)
        state.beginBatch(); state.receive(.init(code: 29), in: clear)
        #expect(state.selected?.art == 2 && state.selected?.guide == 61 && state.selected?.external == true)
        state.beginBatch(); state.receive(.init(code: 34), in: clear)
        #expect(state.selected == nil) // Journal broken-part opcode is not a notification opcode.
    }
}
