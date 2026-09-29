import Testing
@testable import OregonBound

struct OriginalDeathPresentationTests {
    @Test func timerCountsObservedTicksWithoutCatchingUp() {
        var timer = OriginalDialogTimer(ticks: 3)
        timer.advance(to: 100, active: true)
        timer.advance(to: 100, active: true)
        #expect(timer.remainingTicks == 3)
        timer.advance(to: 1000, active: true)
        #expect(timer.remainingTicks == 2)
        timer.advance(to: 1001, active: false)
        timer.advance(to: 5000, active: true)
        #expect(timer.remainingTicks == 2)
        timer.advance(to: 5001, active: true)
        timer.advance(to: 5002, active: true)
        #expect(timer.isFinished)
    }
    @Test func memorialTransitionsAfterSixtyThenFiveHundredFortyTicks() {
        var memorial = OriginalDeathPresentation()
        memorial.advance(to: 0, active: true)
        for tick in 1...59 { memorial.advance(to: tick, active: true) }
        #expect(memorial.phase == .initial)
        memorial.advance(to: 60, active: true)
        #expect(memorial.phase == .mourning && memorial.remainingTicks == 540)
        for tick in 61...599 { memorial.advance(to: tick, active: true) }
        #expect(!memorial.isFinished && memorial.remainingTicks == 1)
        memorial.advance(to: 600, active: true)
        #expect(memorial.isFinished)
    }
    @Test func imageClickDismissesImmediatelyAndDoesNotRepeat() {
        var memorial = OriginalDeathPresentation()
        memorial.dismiss()
        #expect(memorial.isFinished)
        memorial.advance(to: 900, active: true)
        #expect(memorial.isFinished)
    }
    @Test func crossingDefersMemorialAndFinalPartyHasHigherPriority() {
        #expect(OriginalDeathPresentationRules.memorialPlacement(survivors: 2, crossingResultActive: false) == .visible)
        #expect(OriginalDeathPresentationRules.memorialPlacement(survivors: 0, crossingResultActive: false) == .behindPartyLoss)
        #expect(OriginalDeathPresentationRules.memorialPlacement(survivors: 0, crossingResultActive: true) == .deferredUntilCrossingCleanup)
    }
}
