import Foundation
import Testing
@testable import OregonBound

struct OriginalActionSchedulerTests {
    private func stoppedParty() -> Journey {
        var trip = Journey(seed: 41)
        trip.phase = .river; trip.locationID = "kansas"; trip.destinationID = "kansas"
        trip.inventory[.food] = 1000; trip.inventory[.bullets] = 100
        trip.inventory[.clothing] = 10; trip.inventory[.oxen] = 12
        return trip
    }

    @Test func startingHuntDoesNotChargeDateFoodOrWeatherRandomness() throws {
        var trip = stoppedParty()
        trip.phase = .travel; trip.locationID = "independence"; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 20
        trip.original?.weather.category = 0
        let before = trip
        try JourneyEngine.beginHunt(&trip)
        #expect(trip.phase == .hunting)
        #expect(trip.daysElapsed == before.daysElapsed)
        #expect(trip.inventory == before.inventory)
        #expect(trip.randomState == before.randomState)
    }

    @Test func completedHuntQueuesOneRestDayWithoutImmediateDateCharge() throws {
        var trip = stoppedParty()
        trip.phase = .travel; trip.locationID = "independence"; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 20
        trip.original?.weather.category = 0
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.finishHunt(food: 10, shots: 2, in: &trip)
        #expect(trip.phase == .travel && trip.inventory[.food] == 1010)
        #expect(trip.original?.restDays == 1)
        #expect(trip.original!.flags & 4 != 0 && trip.daysElapsed == 0)
    }
    @Test func restQueuesAndResumesThroughCounterZeroCleanupDay() throws {
        var trip = stoppedParty()
        let seed = trip.randomState
        try JourneyEngine.beginRest(days: 3, in: &trip)
        #expect(trip.daysElapsed == 0 && trip.inventory[.food] == 1000 && trip.randomState == seed)
        #expect(trip.original?.restDays == 3 && trip.original!.flags & 4 != 0)
        #expect(trip.journal.last?.text == "You decided to rest for 3 days.")
        for expected in [2,1,0] {
            #expect(JourneyEngine.advanceActionDay(in: &trip))
            #expect(trip.original!.restDays == UInt8(expected) && trip.original!.flags & 4 != 0)
        }
        #expect(trip.daysElapsed == 3)
        var restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(JourneyEngine.advanceActionDay(in: &restored))
        #expect(restored.daysElapsed == 4 && restored.original!.flags & 4 == 0)
        #expect(restored.inventory[.food] == 940)
        let complete = restored
        #expect(!JourneyEngine.advanceActionDay(in: &restored) && restored == complete)
    }

    @Test func timeOutAndTravelBlockDoNotCancelRest() throws {
        var trip = stoppedParty()
        trip.phase = .travel; trip.locationID = "independence"; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 0
        JourneyEngine.resumeTravel(in: &trip)
        try JourneyEngine.beginRest(days: 1, in: &trip)
        JourneyEngine.pauseTravel(in: &trip)
        #expect(trip.original!.flags & 6 == 4)
        #expect(JourneyEngine.advanceActionDay(in: &trip, travelBlocked: true))
        #expect(JourneyEngine.advanceActionDay(in: &trip, travelBlocked: true))
        #expect(trip.daysElapsed == 2 && trip.miles == 0 && trip.original!.flags & 6 == 0)
        #expect(!JourneyEngine.advanceActionDay(in: &trip))
        JourneyEngine.resumeTravel(in: &trip)
        #expect(!JourneyEngine.advanceActionDay(in: &trip, travelBlocked: true))
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.miles > 0)
    }

    @Test func cleanupDayCanResumeMovementWithoutOrdinaryArrivalJournal() throws {
        var trip = stoppedParty()
        trip.phase = .travel; trip.locationID = "independence"; trip.destinationID = "kansas"
        trip.legDistance = 102; trip.legProgress = 81; trip.miles = 81
        JourneyEngine.resumeTravel(in: &trip)
        try JourneyEngine.beginRest(days: 1, in: &trip)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.miles == 81)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.phase == .river && trip.miles == 102 && trip.daysElapsed == 2)
        // CODE16:2640 uses the ENTRY rest flag, even when counters clear it.
        #expect(!trip.journal.contains { $0.text.contains("You have reached") })
    }

    @Test func pureSchedulerGatesAndByteCounterMatchInstructionOrder() {
        #expect(!OriginalActionScheduler.timerPermitsDay(flags: 8)) // delay only
        #expect(!OriginalActionScheduler.timerPermitsDay(flags: 18)) // moving+blocked
        #expect(OriginalActionScheduler.timerPermitsDay(flags: 22)) // rest bypasses block
        let noOxen = OriginalActionScheduler.dayDecision(flags: 2, remainingMiles: 100, minimumRawOxen: 0)
        #expect(noOxen.advancesDate && noOxen.flags == 0 && noOxen.runsEvents)
        let stopped = OriginalActionScheduler.dayDecision(flags: 2, remainingMiles: 0, minimumRawOxen: 12)
        #expect(!stopped.advancesDate && stopped.flags == 0)
        var counter: UInt8 = 0
        #expect(!OriginalActionScheduler.timerPulse(counter: &counter, threshold: 3, flags: 1))
        #expect(!OriginalActionScheduler.timerPulse(counter: &counter, threshold: 3, flags: 1))
        #expect(!OriginalActionScheduler.timerPulse(counter: &counter, threshold: 3, flags: 1))
        #expect(counter == 2)
        #expect(OriginalActionScheduler.timerPulse(counter: &counter, threshold: 3, flags: 5))
        #expect(counter == 0)
        var flags: UInt8 = 6
        var rest: UInt8 = 255
        OriginalActionScheduler.finishHunt(flags: &flags, restDays: &rest)
        #expect(rest == 0 && flags == 6)
        OriginalActionScheduler.requestRest(days: 2, flags: &flags, restDays: &rest)
        #expect(rest == 2 && flags == 6)
        OriginalActionScheduler.pauseTravel(flags: &flags)
        #expect(flags == 4 && rest == 2)
        OriginalActionScheduler.resumeTravel(flags: &flags)
        #expect(flags == 6 && rest == 2)
    }

}
