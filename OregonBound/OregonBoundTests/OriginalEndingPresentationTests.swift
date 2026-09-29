import Testing
@testable import OregonBound

struct OriginalEndingPresentationTests {
    @Test func legendsRequireStrictlyBeatingAnExistingScore() {
        let entries = OriginalEndingPresentation.initialLegends
        #expect(OriginalEndingPresentation.insertionIndex(score: 250, legends: entries) == nil)
        #expect(OriginalEndingPresentation.insertionIndex(score: 251, legends: entries) == 9)
        #expect(OriginalEndingPresentation.insertionIndex(score: 7650, legends: entries) == 1)
        #expect(OriginalEndingPresentation.insertionIndex(score: 7651, legends: entries) == 0)
        #expect(OriginalEndingPresentation.insertionIndex(score: 0, legends: []) == nil)
        #expect(OriginalEndingPresentation.insertionIndex(score: 1, legends: []) == 0)
    }
    @Test(.enabled(if: GameData.isReady)) func scoreRowsMatchOriginalSingularTemplatesAndRawOxen() throws {
        var trip = Journey(profession: .teacher, seed: 1)
        trip.members = [trip.members[0]]
        trip.inventory[.oxen] = 3
        trip.inventory[.wheels] = 1
        trip.inventory[.food] = 26
        trip.cash = 100
        JourneyEngine.finish(&trip, won: true, reason: "Arrived")
        let rows = OriginalEndingPresentation.rows(trip, strings: OriginalResources.strings(3004))
        #expect(rows.count == 8)
        #expect(rows[0].label == "1 person arriving in good health x 500 =")
        #expect(rows[2].label == "2 oxen x 4 =" && rows[2].points == 8)
        // Original STR3004's singular spare-parts string omits '='.
        #expect(rows[3].label == "1 spare wagon part x 2")
        // CODE10 compares cash cents to1, not the displayed whole-dollar amount.
        #expect(rows[7].label == "1 dollars ÷ 5 =")
        #expect(JourneyEngine.score(trip) == (rows.reduce(0) { $0 + $1.points } * 7 + 1) / 2)
    }
}
