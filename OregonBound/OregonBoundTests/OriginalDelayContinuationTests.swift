import Foundation
import Testing
@testable import OregonBound

struct OriginalDelayContinuationTests {
    private func pausedTravel() -> Journey {
        var trip = Journey(seed: 41)
        trip.phase = .travel; trip.locationID = "independence"; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 0
        trip.inventory[.food] = 1000; trip.inventory[.clothing] = 10; trip.inventory[.oxen] = 12
        trip.original?.weather.initialized = true
        trip.original?.flags = 0
        return trip
    }

    @Test func loadedDormantCounterDoesNotReactivateOrChangeRandomContinuation() throws {
        var dormant = pausedTravel()
        dormant.delayDays = 3 // original load clears flags but retains world+6
        let paused = dormant
        #expect(!JourneyEngine.advanceActionDay(in: &dormant))
        #expect(dormant == paused)
        dormant = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(dormant))
        var control = dormant
        control.delayDays = 0
        JourneyEngine.resumeTravel(in: &dormant)
        JourneyEngine.resumeTravel(in: &control)
        #expect(JourneyEngine.advanceActionDay(in: &dormant))
        #expect(JourneyEngine.advanceActionDay(in: &control))
        #expect(dormant.delayDays == 3 && dormant.original!.flags & 8 == 0)
        #expect(dormant.miles == 20 && dormant.randomState == control.randomState)
        dormant.delayDays = 0
        #expect(dormant == control) // health, food, journal, weather, seed and movement
    }

    @Test func restDoesNotActivateDormantDelayCounter() throws {
        var trip = pausedTravel()
        trip.phase = .river; trip.locationID = "kansas"; trip.destinationID = "kansas"
        trip.delayDays = 7
        try JourneyEngine.beginRest(days: 1, in: &trip)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.delayDays == 7 && trip.original!.flags & 8 == 0)
        #expect(JourneyEngine.advanceActionDay(in: &trip)) // rest cleanup
        #expect(trip.delayDays == 7 && trip.original!.flags & 12 == 0)
        let complete = trip
        #expect(!JourneyEngine.advanceActionDay(in: &trip) && trip == complete)
    }

    @Test func explicitDelayKeepsCleanupDayAndDormantRequestComparison() {
        var trip = pausedTravel()
        trip.delayDays = 3
        OriginalTrailEvents.delay(2, in: &trip)
        OriginalTrailEvents.delay(3, in: &trip)
        #expect(trip.delayDays == 3 && trip.original!.flags & 8 == 0)
        OriginalTrailEvents.delay(4, in: &trip)
        #expect(trip.delayDays == 4 && trip.original!.flags & 8 != 0)
        trip.delayDays = 1
        JourneyEngine.resumeTravel(in: &trip)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.delayDays == 0 && trip.original!.flags & 8 != 0 && trip.miles == 0)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.delayDays == 0 && trip.original!.flags & 8 == 0 && trip.miles == 20)
    }

    @Test func legacyJSONWithoutOriginalStateStillMigratesActiveDelay() throws {
        var legacy = pausedTravel()
        legacy.original = nil; legacy.delayDays = 2
        var restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(legacy))
        #expect(restored.original == nil)
        #expect(JourneyEngine.advanceActionDay(in: &restored))
        #expect(restored.delayDays == 1 && restored.original!.flags & 8 != 0)
        #expect(restored.daysElapsed == 1 && restored.miles == 0)
    }
}
