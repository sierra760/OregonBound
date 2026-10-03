import Testing
@testable import OregonBound

struct OriginalEndingPresentationTests {
    @Test(arguments: [(24,24,0,0), (25,49,1,1), (49,25,1,1), (2000,1000,80,40)])
    func cdScoresEachFoodPoolBeforeAdding(_ stored: Int, _ fresh: Int, _ storedPoints: Int, _ freshPoints: Int) {
        var trip = Journey(profession: .teacher, seed: 1, edition: .macintoshCD12)
        trip.inventory[.food] = stored; trip.inventory.perishableFood = fresh
        JourneyEngine.finish(&trip, won: true, reason: "Arrived")
        let lines = JourneyEngine.scoreLines(trip)
        #expect(lines.count == 9)
        #expect(lines.first { $0.id == "Non-perishable food" }?.points == storedPoints)
        #expect(lines.first { $0.id == "Perishable food" }?.points == freshPoints)
        #expect(JourneyEngine.score(trip) == (lines.reduce(0) { $0 + $1.points } * 7 + 1) / 2)
        trip.edition = .macintosh11
        #expect(JourneyEngine.scoreLines(trip).count == 8)
        #expect(JourneyEngine.scoreLines(trip).first { $0.id == "Food" }?.points == storedPoints)
    }

    @Test func cdScoreTemplatesUseEightEntrySingularOffsetAndSeparateFoodRows() {
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        trip.members = [trip.members[0]]; trip.inventory[.food] = 1; trip.inventory.perishableFood = 26
        trip.cash = 100
        JourneyEngine.finish(&trip, won: true, reason: "Arrived")
        let strings = (0..<29).map { "row\($0) ^0 ^1" }
        let rows = OriginalEndingPresentation.rows(trip, strings: strings)
        #expect(rows.count == 9)
        #expect(rows.first?.label == "1row18 good 500")
        #expect(rows.first { $0.id == 6 }?.label == "1row23 good 25")
        #expect(rows.first { $0.id == 7 }?.label == "26row16 good 25")
        #expect(rows.last?.label == "1row17 good 5")
        #expect(rows.map(\.points) == JourneyEngine.scoreLines(trip).map(\.points))
        trip.cash = 1; trip.inventory.perishableFood = 1
        let singular = OriginalEndingPresentation.rows(trip, strings: strings)
        #expect(singular.first { $0.id == 7 }?.label == "1row24 good 25")
        #expect(singular.last?.label == "0row25 good 5")
        #expect(OriginalEndingPresentation.rows(trip, strings: Array(strings.prefix(25))).isEmpty)
    }

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

struct OriginalStatusContentTests {
    @Test func cdStatusUsesAllEightItemsAndItsOwnSingularTable() {
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        for item in 0..<8 { trip.inventory[originalIndex: item] = 1 }
        let strings = (0..<18).map { "label\($0)" }
        let rows = OriginalStatusPane.supplyRows(trip, strings: strings)
        #expect(OriginalStatusPane.supplyStringsID(for: trip.gameEdition) == 3030)
        #expect(rows.count == 8)
        #expect(rows.map(\.label) == (8..<16).map { "label\($0)" })
        #expect(rows.map(\.count) == Array(repeating: 1, count: 8))
        #expect(OriginalStatusPane.moneyBaseline(for: trip.gameEdition) == 173)
        trip.inventory[.food] = 26; trip.inventory.perishableFood = 49
        #expect(trip.totalFood == 75)
        #expect(OriginalStatusPane.supplyRows(trip, strings: strings).suffix(2).map(\.label) == ["label6","label7"])
        trip.edition = .macintosh11
        #expect(trip.totalFood == 26)
        #expect(OriginalStatusPane.supplyRows(trip, strings: strings).count == 7)
        #expect(OriginalStatusPane.supplyStringsID(for: trip.gameEdition) == 3011)
        #expect(OriginalStatusPane.moneyBaseline(for: trip.gameEdition) == 159)
    }
}
