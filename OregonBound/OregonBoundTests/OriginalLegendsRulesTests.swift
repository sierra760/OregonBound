import Testing
@testable import OregonBound

struct OriginalLegendsRulesTests {
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
