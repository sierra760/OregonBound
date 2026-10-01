import Foundation
import Testing
@testable import OregonBound

struct OriginalRandomStreamTests {
    @MainActor @Test func sharedConsumersPreserveInterleavedDrawsIncludingSpanOne() {
        let stream = OriginalRandomStream(seed: 17)
        var expected = OriginalRandom(seed: 17)
        let title: (Int)->Int = { stream.bounded($0) }
        let hunt: (Int)->Int = { stream.bounded($0) }
        #expect(title(300) == expected.bounded(300))
        let saved = stream.seed
        #expect(hunt(1) == 0)
        _ = expected.next()
        #expect(stream.seed == expected.seed && stream.seed != saved)
        #expect(hunt(50) == expected.bounded(50))
        // Model days retain value semantics; controller brackets a synchronous action.
        var day = OriginalRandom(seed: stream.seed)
        #expect(day.bounded(100) == expected.bounded(100))
        stream.seed = day.seed
        #expect(hunt(7) == expected.bounded(7)); #expect(stream.seed == expected.seed)
    }
    @Test func originalClockUsesWholeLocalSecondsAndWrapsUnsignedWord() {
        let utc = TimeZone(secondsFromGMT: 0)!
        #expect(OriginalRandomStream.clockSeed(date: Date(timeIntervalSince1970: 0.9),timeZone: utc) == 2_082_844_800)
        #expect(OriginalRandomStream.clockSeed(date: Date(timeIntervalSince1970: 0),timeZone: TimeZone(secondsFromGMT: -8*3600)!) == 2_082_816_000)
        #expect(OriginalRandomStream.clockSeed(date: Date(timeIntervalSince1970: -2_082_844_800),timeZone: utc) == 0)
        #expect(OriginalRandomStream.clockSeed(date: Date(timeIntervalSince1970: 4_294_967_296-2_082_844_800),timeZone: utc) == 0)
    }
    @Test func onshoreNeedsTwoIndependentSixtyTickCallbacks() {
        var state = OriginalRaftPresentation()
        #expect(state.advance(to: 0,active: true) == nil)
        for t in 1..<30 { #expect(state.advance(to: t,active: true) == nil) }
        #expect(state.advance(to: 30,active: true) == .beginRafting)
        state.raftingFinished(survivors: 1)
        // Timer records advance once per observed increase, not elapsed time.
        #expect(state.advance(to: 999,active: true) == nil)
        for t in 1000..<1058 { #expect(state.advance(to: t,active: true) == nil) }
        #expect(state.advance(to: 1058,active: true) == .submitLosses)
        #expect(state.phase == .onshore)
        #expect(state.advance(to: 1058,active: true) == nil)
        for t in 1059..<1118 { #expect(state.advance(to: t,active: true) == nil) }
        #expect(state.advance(to: 1118,active: true) == .complete)
        #expect(state.advance(to: 1119,active: true) == nil)
    }
    @Test func noSurvivorsSkipOnshoreHold() {
        var state = OriginalRaftPresentation()
        for t in 0...30 { _ = state.advance(to: t,active: true) }
        state.raftingFinished(survivors: 0)
        #expect(state.advance(to: 31,active: true) == .complete)
    }
}

struct OriginalHuntDeferredRandomTests {
    private var input: OriginalHuntSession.Input {
        .init(destination: 3,month: 4,weatherCategory: 0,snow: false,mileage: 100,lastSuccessfulHuntMileage: 0,
              ammunition: 100,survivors: 5,currentFood: 500,foodCapacity: 2000,timeSetting: 3,originalDisplayFlag: true)
    }
    @Test func preparationConsumesPopulationButDefersSceneryDrawsUntilShown() {
        var eagerRandom = OriginalRandom(seed: 7)
        let eager = OriginalHuntSession(input: input,startTick: 0) { eagerRandom.bounded($0) }
        var deferredRandom = OriginalRandom(seed: 7)
        var deferred = OriginalHuntSession(input: input,startTick: 0,deferInitialScenery: true) { deferredRandom.bounded($0) }
        #expect(deferred.population == eager.population)
        #expect(deferred.objects.count == 2)
        #expect(deferredRandom.seed != eagerRandom.seed)
        deferred.beginScene { deferredRandom.bounded($0) }
        #expect(deferred.objects == eager.objects); #expect(deferredRandom.seed == eagerRandom.seed)
        deferred.beginScene { _ in Issue.record("Scene start repeated RNG"); return 0 }
    }
}
