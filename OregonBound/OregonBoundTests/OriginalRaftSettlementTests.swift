import Foundation
import Testing
@testable import OregonBound

struct OriginalRaftSettlementTests {
    private func trip() throws -> Journey {
        var value = Journey(profession: .banker,difficulty: .greenhorn,names: ["A","B","C"],seed: 42)
        value.locationID = "dalles"; value.phase = .fork
        value.inventory[.oxen] = 3; value.inventory[.food] = 1000
        value.daysElapsed = 364; value.miles = 1940
        value.ensureOriginalState(); value.original?.badness = 130
        try JourneyEngine.beginRaft(&value)
        return value
    }
    @Test func actualSnapshotSettlesWithoutInventedDaysOrMilesAndCapsDeathBadness() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        var remaining = input.inventory; remaining[0] = 1; remaining[6] = 990
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: remaining,
                                                initialLiving: input.living,drownedMembers: [1])
        let restored = try JSONDecoder().decode(OriginalRaftSession.Result.self,from: JSONEncoder().encode(result))
        try JourneyEngine.finishRaft(result: restored,randomSeed: 17,in: &value)
        #expect(value.won); #expect(value.phase == .finished)
        #expect(value.daysElapsed == 364); #expect(value.miles == 1940)
        #expect(value.inventory[.food] == 990); #expect(value.inventory[.oxen] == 1)
        #expect(value.healthBadness == 105); #expect(!value.members[1].alive)
        #expect(value.randomState == 17)
        try JourneyEngine.finishRaft(result: restored,randomSeed: 99,in: &value)
        #expect(value.randomState == 17) // Late duplicate callback cannot replace newer seed.
    }
    @Test func forgedOrStaleResultsAreRejectedBeforeAnyMutation() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        var remaining = input.inventory; remaining[6] += 1
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: remaining,
                                                initialLiving: input.living,drownedMembers: [])
        #expect(throws: GameRuleError.self) { try JourneyEngine.finishRaft(result: result,randomSeed: 17,in: &value) }
        #expect(value.phase == .rafting); #expect(value.inventory[.food] == 1000)
        #expect(value.randomState == 42)
    }
    @Test func allDeathsLoseWithoutAdvancingDays() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: input.inventory,
                                                initialLiving: input.living,drownedMembers: [0,1,2])
        try JourneyEngine.finishRaft(result: result,randomSeed: 18,in: &value)
        #expect(!value.won); #expect(value.livingMembers.isEmpty); #expect(value.healthBadness == 105)
        #expect(value.daysElapsed == 364)
    }
    @Test func twoPhaseSubtractsFromCurrentFoodAndDoesNotApplyTwice() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        var remaining = input.inventory; remaining[6] = 20
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: remaining,
                                                initialLiving: input.living,drownedMembers: [])
        // A queued rest day consumes food after packet creation during the onshore wait.
        try JourneyEngine.prepareRaftLanding(result: result,in: &value)
        value.inventory[.food] = 970
        #expect(JourneyEngine.originalRaftInput(value).inventory[6] == 1000)
        #expect(try JourneyEngine.applyRaftLosses(result: result,in: &value))
        #expect(value.inventory[.food] == 0) // max(0,current970−loss980), not copy20.
        #expect(value.phase == .rafting); #expect(!value.won)
        let journalCount = value.journal.count
        #expect(try !JourneyEngine.applyRaftLosses(result: result,in: &value))
        #expect(value.journal.count == journalCount)
        let restored = try JSONDecoder().decode(Journey.self,from: JSONEncoder().encode(value))
        #expect(restored.originalRaftState?.appliedResult == result)
        try JourneyEngine.completeRaftLanding(in: &value)
        #expect(value.won); #expect(value.originalRaftState == nil)
        try JourneyEngine.completeRaftLanding(in: &value) // Callback delivery is idempotent.
    }
    @Test func restBeforePacketCreationProducesSignedNegativeLoss() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: input.inventory,
                                                initialLiving: input.living,drownedMembers: [])
        value.inventory[.food] = 970
        try JourneyEngine.prepareRaftLanding(result: result,in: &value)
        #expect(value.originalRaftState?.commandQuantities?[6] == -30)
        value.inventory[.food] = 955 // Another rest day during onshore wait.
        _ = try JourneyEngine.applyRaftLosses(result: result,in: &value)
        #expect(value.inventory[.food] == 985) // Live955 − signed packet(−30).
    }
    @Test func restDeathIsNeverResurrectedOrAnnouncedTwice() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: input.inventory,
                                                initialLiving: input.living,drownedMembers: [1])
        value.members[1].health = 0
        let journalCount = value.journal.count
        _ = try JourneyEngine.applyRaftLosses(result: result,in: &value)
        #expect(!value.members[1].alive); #expect(value.journal.count == journalCount)
        #expect(value.healthBadness == 130) // No new death helper invocation.
        try JourneyEngine.completeRaftLanding(in: &value)
        #expect(value.livingMembers.count == 2)
    }
    @Test func separateDailyGameOverMakesLateSceneCallbacksHarmless() throws {
        var value = try trip()
        let input = JourneyEngine.originalRaftInput(value)
        let result = OriginalRaftSession.Result(initialInventory: input.inventory,remainingInventory: input.inventory,
                                                initialLiving: input.living,drownedMembers: [])
        for index in value.members.indices { value.members[index].health = 0 }
        JourneyEngine.finish(&value,won: false,reason: "The party died during a rest day.")
        #expect(try !JourneyEngine.applyRaftLosses(result: result,in: &value))
        try JourneyEngine.completeRaftLanding(in: &value)
        #expect(!value.won); #expect(value.originalRaftState == nil)
        #expect(value.finishReason == "The party died during a rest day.")
    }
    @Test func completionRequiresFirstSettlementCallback() throws {
        var value = try trip()
        #expect(throws: GameRuleError.self) { try JourneyEngine.completeRaftLanding(in: &value) }
        #expect(value.phase == .rafting)
    }

}
