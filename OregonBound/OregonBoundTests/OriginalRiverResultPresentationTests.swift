import Testing
@testable import OregonBound

struct OriginalRiverResultPresentationTests {
    @Test func safeUsesThreeThen177ObservedAdvancesAndFinishesOnce() {
        var model = OriginalRiverResultPresentation(isFailure: false, presentationRandomTicks: nil, observedTick: 0)
        #expect(model.initialTicks == 3 && !model.usedLegacyFallback)
        for tick in 1...2 { #expect({ !model.advance(to: tick) }()) }
        #expect(model.phase == .initial && model.ticksRemaining == 1)
        #expect({ !model.advance(to: 3) }())
        #expect(model.phase == .remaining && model.ticksRemaining == 177)
        for tick in 4...179 { #expect({ !model.advance(to: tick) }()) }
        #expect({ model.advance(to: 180) }())
        #expect(model.phase == .finished)
        #expect({ !model.advance(to: 181) }())
        model.requestDismissal()
        #expect({ !model.advance(to: 182) }())
    }

    @Test(arguments: [1, 37, 90, 179])
    func failureUsesSavedDrawAndFinishesAt180(initial: Int) {
        var model = OriginalRiverResultPresentation(isFailure: true, presentationRandomTicks: initial, observedTick: 0)
        #expect(model.initialTicks == initial && !model.usedLegacyFallback)
        for tick in 1...initial { #expect({ !model.advance(to: tick) }()) }
        #expect(model.phase == .remaining && model.ticksRemaining == 180-initial)
        if initial < 179 {
            for tick in (initial+1)...179 { #expect({ !model.advance(to: tick) }()) }
        }
        #expect({ model.advance(to: 180) }())
    }

    @Test func zeroInitialFiresAtSameTickButReplacementDoesNotFireInSamePass() {
        var model = OriginalRiverResultPresentation(isFailure: true, presentationRandomTicks: 0, observedTick: 100)
        #expect({ !model.advance(to: 100) }())
        #expect(model.phase == .remaining && model.ticksRemaining == 180)
        #expect({ !model.advance(to: 100) }())
        #expect(model.ticksRemaining == 180)
        for tick in 101...279 { #expect({ !model.advance(to: tick) }()) }
        #expect({ model.advance(to: 280) }())
    }

    @Test func delayedIdleCountsOnceAndRepeatedOrRegressedTicksDoNotAdvance() {
        var model = OriginalRiverResultPresentation(isFailure: false, presentationRandomTicks: nil, observedTick: 10)
        #expect({ !model.advance(to: 10000) }())
        #expect(model.ticksRemaining == 2)
        #expect({ !model.advance(to: 10000) }())
        #expect({ !model.advance(to: 9999) }())
        #expect({ !model.advance(to: 10000) }())
        #expect(model.ticksRemaining == 2)
        #expect({ !model.advance(to: 10001) }())
        #expect(model.ticksRemaining == 1)
    }

    @Test(arguments: [false, true])
    func okReplacesEitherPhaseWithZeroAndFinishesOnNextIdle(inSecondPhase: Bool) {
        var model = OriginalRiverResultPresentation(isFailure: false, presentationRandomTicks: nil, observedTick: 0)
        if inSecondPhase { for tick in 1...3 { _ = model.advance(to: tick) } }
        model.requestDismissal()
        model.requestDismissal() // queued duplicate OK does not itself complete
        #expect(model.phase == .remaining && model.ticksRemaining == 0)
        #expect({ model.advance(to: inSecondPhase ? 3 : 0) }())
        #expect({ !model.advance(to: inSecondPhase ? 3 : 0) }())
    }

    @Test func modalSkipsObservationWhileInactiveReanchorsAsNativePolicy() {
        var model = OriginalRiverResultPresentation(isFailure: false, presentationRandomTicks: nil, observedTick: 10)
        #expect({ !model.advance(to: 500, modalBlocked: true) }())
        model.requestDismissal(modalBlocked: true)
        #expect(model.phase == .initial && model.ticksRemaining == 3)
        #expect({ !model.advance(to: 500) }()) // resumed modal contributes one, not490
        #expect(model.ticksRemaining == 2)
        #expect({ !model.advance(to: 600, active: false) }())
        model.requestDismissal(active: false)
        #expect({ !model.advance(to: 700) }()) // inactive pause deliberately reanchors
        #expect(model.ticksRemaining == 2)
        #expect({ !model.advance(to: 701) }())
        #expect(model.ticksRemaining == 1)
    }

    @Test func zeroIntervalStillWaitsForActiveNonmodalIdle() {
        var model = OriginalRiverResultPresentation(isFailure: false, presentationRandomTicks: nil)
        model.requestDismissal()
        #expect({ !model.advance(to: 100, active: false) }())
        #expect({ !model.advance(to: 100, modalBlocked: true) }())
        #expect({ model.advance(to: 100) }()) // does not require an established anchor
    }

    @Test func legacyMissingDrawUsesExplicitDeterministicFallback() {
        var missing = OriginalRiverResultPresentation(isFailure: true, presentationRandomTicks: nil, observedTick: 0)
        #expect(missing.initialTicks == 3 && missing.usedLegacyFallback)
        for tick in 1...179 { #expect({ !missing.advance(to: tick) }()) }
        #expect({ missing.advance(to: 180) }())
    }
}
