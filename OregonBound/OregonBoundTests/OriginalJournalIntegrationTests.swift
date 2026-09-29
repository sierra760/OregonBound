import Foundation
import Testing
@testable import OregonBound

struct OriginalJournalIntegrationTests {
    @Test func recoveredEventFacesSurviveSaveWithoutGuessingLegacyFormatting() throws {
        var trip = Journey(seed: 42)
        OriginalTrailEvents.record(0, in: &trip)
        OriginalTrailEvents.record(23, in: &trip)
        OriginalTrailEvents.record(64, cash: 100, in: &trip)
        OriginalTrailEvents.record(44, in: &trip)
        let data = try JSONEncoder().encode(trip.journal)
        let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rows.map { $0["originalBold"] as? Bool } == [false, true, true, false])
        let restored = try JSONDecoder().decode([JournalEntry].self, from: data)
        #expect(restored == trip.journal)
        let legacy = Data(#"[{"id":0,"day":0,"text":"Old entry"}]"#.utf8)
        let decoded = try JSONDecoder().decode([JournalEntry].self, from: legacy)
        #expect(decoded.map(\.text) == ["Old entry"])
    }

    @Test func huntRejectsEveryStoppedLandmarkWithoutChangingState() {
        // CODE6:096e reads remaining byte, not a distance-to-town threshold.
        for stop in TrailCatalog.stops.dropLast() {
            for phase in [JourneyPhase.landmark, .river, .fork] {
                var trip = Journey(seed: 42)
                trip.phase = phase; trip.locationID = stop.id; trip.destinationID = stop.id
                trip.inventory[.bullets] = 100
                trip.original?.weather.category = 0
                #expect(trip.huntEligibility == .occupiedLandmark)
                #expect(!trip.canHunt)
                let before = trip
                #expect(throws: GameRuleError.self) { try JourneyEngine.beginHunt(&trip) }
                #expect(trip == before)
            }
        }
    }

    @Test func liveRawWeatherAndRemainingMilesControlHuntPriority() throws {
        var trip = Journey(seed: 42)
        trip.phase = .travel; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 101
        trip.inventory[.bullets] = 0
        for category: UInt8 in [7,8,9,0x87,0x88,0x89] {
            trip.original?.weather.category = category
            #expect(trip.huntEligibility == .severeWeather)
            let before = trip
            #expect(throws: GameRuleError.self) { try JourneyEngine.beginHunt(&trip) }
            #expect(trip == before)
        }
        trip.original?.weather.category = 0
        #expect(trip.huntEligibility == .noBullets)
        trip.inventory[.bullets] = 1
        #expect(trip.huntEligibility == .allowed && trip.canHunt)
        let before = trip
        try JourneyEngine.beginHunt(&trip)
        #expect(trip.miniGameReturnPhase == .travel && trip.phase == .hunting)
        #expect(trip.randomState == before.randomState && trip.daysElapsed == before.daysElapsed)
        #expect(trip.journal.last?.text == "You decided to hunt.")
    }

    @Test func departureUsesPackedOriginalSupplyListAndOmitsZeroSupplies() throws {
        var trip = Journey(seed: 42)
        trip.phase = .departure
        trip.inventory[.oxen] = 12; trip.inventory[.food] = 1000; trip.cash = 114000
        try JourneyEngine.chooseDeparture(month: 4,in: &trip)
        #expect(trip.journal.map(\.text) == ["You started down the trail with 6 oxen, 1,000 pounds of food, and $1,140.00."])
        try JourneyEngine.depart(&trip)
        #expect(trip.journal.last?.text == "You decided to continue.")
    }

    @Test func journalFinalizationAndCurrentWagonDeathUseOriginalFormatter() {
        var trip = Journey(seed: 42)
        trip.record("Heavy fog")
        trip.record("z")
        #expect(trip.journal.suffix(2).map(\.text) == ["Heavy fog.","z"])
        OriginalTrailEvents.record(44,in: &trip)
        #expect(trip.journal.last?.text == "Everyone in your wagon has died.")
        // CODE16:14e4→1b50→294a packs member index, CODE14:1e96–1f46 decodes it
        // as event53's count. Preserve the source's misleading raft journal.
        OriginalTrailEvents.record(53,member: 0,in: &trip)
        #expect(trip.journal.last?.text == "0 member of your wagon drowned.")
        OriginalTrailEvents.record(53,member: 2,in: &trip)
        #expect(trip.journal.last?.text == "2 members of your wagon drowned.")
    }
}
