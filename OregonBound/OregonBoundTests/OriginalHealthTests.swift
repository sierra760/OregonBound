import Testing
@testable import OregonBound

struct OriginalHealthTests {
    @Test(arguments: [0, 34, 35, 69, 70, 104, 105, 139])
    func originalBandsAndPersonScores(_ raw: Int) {
        let badness = UInt8(raw)
        #expect(OriginalHealth.band(for: badness)?.rawValue == raw / 35)
        #expect(OriginalHealth.scorePerSurvivor(badness: badness) == 500 - (raw / 35) * 100)
    }

    @Test func lastPoundStillUsesTheSelectedRationPenalty() {
        var input = OriginalHealth.Input()
        input.food = 1
        let lastFood = OriginalHealth.transition(input)
        #expect(lastFood.food == 0)
        #expect(lastFood.badness == 2)
        input.food = 0
        let starving = OriginalHealth.transition(input)
        #expect(starving.badness == 19)
        #expect(starving.auxiliary == 1)
    }

    @Test(arguments: [UInt8(4), UInt8(8)])
    func restingAndDelayedRetainWeatherAndRationPenalties(_ flags: UInt8) {
        var input = OriginalHealth.Input()
        input.badness = 50
        input.pace = 2
        input.stateFlags = flags
        input.weather = 5
        input.rations = 2
        let output = OriginalHealth.transition(input)
        #expect(output.badness == 51) // 45 retained +2 snow +4 bare bones
        #expect(output.food == 95)
        #expect(output.terms.paceAndWeather == 2)
    }

    @Test func auxiliaryNegativeNumeratorTruncatesTowardZero() {
        var input = OriginalHealth.Input()
        #expect(OriginalHealth.transition(input).auxiliary == 0)
        input.auxiliary = 5
        #expect(OriginalHealth.transition(input).auxiliary == 2)
    }

    @Test func thresholdIsStrictlyGreaterThan139() {
        var input = OriginalHealth.Input()
        input.pendingEventPenalty = 137 // steady2 +137 =139
        #expect(!OriginalHealth.transition(input).thresholdCrossed)
        input.pendingEventPenalty = 138
        let output = OriginalHealth.transition(input)
        #expect(output.storedBadnessBeforeThreshold == 140)
        #expect(output.thresholdCrossed)
        #expect(output.badness == 139)
    }

    @Test func byteWrapOccursBeforeTheThresholdComparison() {
        var input = OriginalHealth.Input()
        input.pendingEventPenalty = 255
        let output = OriginalHealth.transition(input)
        #expect(output.terms.sum == 257)
        #expect(output.storedBadnessBeforeThreshold == 1)
        #expect(output.badness == 1)
        #expect(!output.thresholdCrossed)
        #expect(output.pendingEventPenalty == 0)
    }

    @Test func oldBadnessIsCappedBeforeDecay() {
        var input = OriginalHealth.Input()
        input.badness = 255
        input.stateFlags = 4
        #expect(OriginalHealth.transition(input).badness == 125)
        #expect(OriginalHealth.band(for: 140) == nil)
    }

    @Test func recoveryDayStillAddsAConditionPenaltyAndTimerWraps() {
        var input = OriginalHealth.Input()
        input.members = [
            .init(condition: 255, remainingDays: 0),
            .init(condition: 4, remainingDays: 1),
            .init(condition: 9, remainingDays: 0),
            .init(condition: 2, remainingDays: 0)
        ]
        let output = OriginalHealth.transition(input)
        #expect(output.terms.activeConditions == 2)
        #expect(output.recoveredMemberIndices == [1])
        #expect(output.members[1].condition == 255)
        #expect(output.members[3].remainingDays == 255)
        #expect(output.members[2].condition == 9)
    }

    @Test func clothingDivisionUsesTheSurvivingCount() {
        var input = OriginalHealth.Input()
        input.temperature = 0
        input.clothing = 14
        let output = OriginalHealth.transition(input)
        #expect(output.terms.clothing == 3) // 5 -0 -floor(14/5)
        #expect(output.badness == 8) // cold2 +clothing3 +pace2 +aux1
    }
}
