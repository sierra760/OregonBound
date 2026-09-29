import Testing
@testable import OregonBound

struct OriginalModalTimingTests {
    @Test func modalGapPreservesObservedTimerAnchorAndConsumesOnlyOneTick() {
        // CODE5:2272–2286 compares against the last observed TickCount. A modal
        // performs no timer call, including no native active:false reset.
        var timer = OriginalDialogTimer(ticks: 180)
        timer.advance(to: 10,active: true)
        timer.advance(to: 11,active: true)
        #expect(timer.remainingTicks == 179)
        timer.advance(to: 10_000,active: true)
        #expect(timer.remainingTicks == 178)
        timer.advance(to: 10_000,active: true)
        #expect(timer.remainingTicks == 178)
    }

    @Test func huntAbsoluteDeadlineExpiresAcrossMissingModalDispatch() {
        let input = OriginalHuntSession.Input(destination: 2,month: 4,weatherCategory: 0,
            snow: false,mileage: 20,lastSuccessfulHuntMileage: 20,ammunition: 99,
            survivors: 5,currentFood: 0,foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: false)
        var random = OriginalRandom(seed: 1234)
        var hunt = OriginalHuntSession(input: input,startTick: 0) { random.bounded($0) }
        let deadline = hunt.endTick
        // Modal time is intentionally NOT setPaused: CODE13:0ece compares real
        // TickCount against the original deadline, even after missed callbacks.
        hunt.advance(to: deadline+60) { _ in 0 }
        #expect(hunt.endTick == deadline && !hunt.isComplete)
        #expect(hunt.nextTick == deadline+63)
        hunt.advance(to: deadline+63) { _ in Issue.record("Settlement must not draw"); return 0 }
        #expect(hunt.isComplete)
    }

    @Test func raftResumesWithOneOverdueUpdateWithoutClockRebasing() {
        let input = OriginalRaftSession.Input(inventory: [12,10,100,1,1,1,1000],
            living: [true],names: ["A"],rain: 400)
        var initial = [0,4]
        var raft = OriginalRaftSession(input: input,startTick: 0) { _ in initial.removeFirst() }
        // No dispatch while modal. CODE17:05bc assigns fresh now+3 after one step.
        raft.advance(to: 10_000,mouseX: nil) { _ in 39 }
        #expect(raft.remaining == 1338 && raft.nextTick == 10_003)
        raft.advance(to: 10_000,mouseX: nil) { _ in Issue.record("No catch-up"); return 0 }
        #expect(raft.remaining == 1338)
    }
}
