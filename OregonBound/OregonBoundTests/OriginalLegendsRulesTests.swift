import Testing
@testable import OregonBound

struct OriginalLegendsRulesTests {
    @Test(arguments: [true, false]) func cdAttractTimerCapturesSoundAndResetsBusyRetries(sound: Bool) {
        var state = CDAttractPresentation(sound: sound, at: 0)
        let titleTicks = sound ? 300 : 600
        for tick in 1..<titleTicks { #expect(state.poll(at: UInt32(tick), sound: sound, busy: true) == false) }
        #expect(state.poll(at: UInt32(titleTicks), sound: sound, busy: true) == !sound)
        if sound {
            for tick in 301..<600 { #expect(state.poll(at: UInt32(tick), sound: true, busy: false) == false) }
            #expect(state.poll(at: 600, sound: true, busy: false) == true)
        }
        state.advance(sound: false, at: 600)
        #expect(state.page == .legends)
        // Muted creation captures 3600 even if sound is enabled afterwards.
        for tick in 601..<4200 { #expect(state.poll(at: UInt32(tick), sound: true, busy: false) == false) }
        #expect(state.poll(at: 4200, sound: true, busy: false) == true)
        state.advance(sound: true, at: 4200)
        #expect(state.page == .title)
        for tick in 4201..<4500 { #expect(state.poll(at: UInt32(tick), sound: false, busy: true) == false) }
        #expect(state.poll(at: 4500, sound: false, busy: true) == true)
    }

    @Test func cdAttractCountsDistinctAdvancingTicksWithoutCatchup() {
        var state = CDAttractPresentation(sound: true, at: 100)
        for _ in 0..<600 { #expect(state.poll(at: 100, sound: true, busy: false) == false) }
        #expect(state.poll(at: 99, sound: true, busy: false) == false)
        #expect(state.poll(at: 10000, sound: true, busy: false) == false)
        for tick in 10001..<10299 { #expect(state.poll(at: UInt32(tick), sound: true, busy: false) == false) }
        #expect(state.poll(at: 10299, sound: true, busy: false) == true)
    }

    @Test func originalClassBoundariesAndScoreFormatting() {
        #expect(OriginalLegendsRules.classification(score: 2999) == "Greenhorn")
        #expect(OriginalLegendsRules.classification(score: 3000) == "Adventurer")
        #expect(OriginalLegendsRules.classification(score: 5999) == "Adventurer")
        #expect(OriginalLegendsRules.classification(score: 6000) == "Trail Guide")
        #expect(OriginalLegendsRules.classification(score: 9000) == "Trail Guide")
        #expect(OriginalLegendsRules.scoreText(7650) == "7,650")
        #expect(OriginalLegendsRules.scoreText(250) == "250")
        #expect(OriginalLegendsRules.scoreText(1_000_000) == "1,000,000")
    }
    @Test func authoredRowsKeepExistingRankAndName() {
        let rows = OriginalLegendsRules.rows(OriginalEndingPresentation.initialLegends)
        #expect(rows.count == 10)
        #expect(rows[0].rank == "1." && rows[0].name == "Stephen Meek")
        #expect(rows[0].classification == "Trail Guide" && rows[0].points == "7,650")
        #expect(rows[1].classification == "Adventurer")
        #expect(rows[3].classification == "Greenhorn")
        #expect(rows[9].rank == "10." && rows[9].points == "250")
        #expect(OriginalLegendsRules.rows([]).isEmpty)
    }
    @Test func titleAndLegendsAttractDurations() {
        #expect(OriginalLegendsRules.AttractPage.title.durationTicks == 7200)
        #expect(OriginalLegendsRules.AttractPage.legends.durationTicks == 600)
        #expect(OriginalLegendsRules.AttractPage.title.next == .legends)
        #expect(OriginalLegendsRules.AttractPage.legends.next == .title)
    }
    @Test func recoveredListCoordinates() {
        #expect(OriginalLegendsRules.rowTop(0) == 112)
        #expect(OriginalLegendsRules.rowTop(9) == 247)
        #expect(OriginalLegendsRules.emptyMessageTop == 157)
    }
}
