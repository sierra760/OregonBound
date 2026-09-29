import Testing
@testable import OregonBound

struct OriginalHuntEligibilityTests {
    @Test func severeWeatherWinsOverLandmarkAndAmmoChecks() {
        for category: UInt8 in 0...6 {
            #expect(OriginalHuntEligibility.evaluate(weatherCategory: category,milesRemaining: 1,ammunition: 1) == .allowed)
        }
        for category: UInt8 in 7...9 {
            #expect(OriginalHuntEligibility.evaluate(weatherCategory: category,milesRemaining: 0,ammunition: 0) == .severeWeather)
        }
    }
    @Test func everyLandmarkBlocksAndOneMileAwayAllowsHunting() {
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 0,ammunition: 0) == .occupiedLandmark)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: 1) == .allowed)
        #expect(OriginalHuntEligibility.Decision.occupiedLandmark.notice(landmarkName: "the Kansas River Crossing") == "Hunting is not allowed near the Kansas River Crossing, because there are too many people around")
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: -1) == .noBullets)
    }
    @Test func originalBusyFlagChecksHaveDistinctPriorityAndResponse() {
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 0,ammunition: 0,playerFlags: 0x80) == .silentBusy)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: 0,playerFlags: 0x10) == .noBullets)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: 1,playerFlags: 0x10) == .beepBusy)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: 1,playerActionFlags: 2) == .beepBusy)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 0,milesRemaining: 1,ammunition: 1,playerActionFlags: 4) == .allowed)
    }
}
