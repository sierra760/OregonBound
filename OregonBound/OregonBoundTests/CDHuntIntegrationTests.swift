import Foundation
import SpriteKit
import Testing
@testable import OregonBound

struct CDHuntIntegrationTests {
    @MainActor @Test func sceneUsesCDRulesAndReseedsBeforeDeferringScenery() throws {
        let input = OriginalHuntSession.Input(destination: 2,month: 4,weatherCategory: 0,snow: true,
            mileage: 123,lastSuccessfulHuntMileage: 100,ammunition: 20,survivors: 5,currentFood: 0,
            foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: true,edition: .macintoshCD12,rain: 41)
        let random = OriginalRandomStream(seed: 999)
        let scene = try OriginalHuntScene(input: input,random: random,cdAssets: CDHuntSessionTests.assets(),startTick: 1234) { _ in }
        var expected = OriginalRandom(seed: 1234)
        var terrain = OriginalRandom(seed: 123)
        let habitat = CDHuntRules.habitat(destination: 2,rain: 41) { terrain.bounded($0) }
        let population = CDHuntRules.population(destination: 2,month: 4,habitat: habitat,repeated: false) { expected.bounded($0) }
        let cd = try #require(scene.session as? CDHuntSession)
        #expect(cd.population == population && cd.habitat == habitat && cd.isPaused)
        #expect(cd.backgroundResource == 19200+10*habitat+3)
        #expect(random.seed == expected.seed)
        #expect(cd.drawCommands.count == 1)
        #expect(cd.backgroundLine?.rect == .init(x: 9,y: 267,width: 494,height: 1))
        #expect(cd.renderViewport == .init(x: 9,y: 9,width: 494,height: 259))
        let mask = try #require((scene.children.first as? SKCropNode)?.maskNode as? SKSpriteNode)
        #expect(mask.position.y == 183.5 && mask.size.height == 259)
    }

    @MainActor @Test func cdSceneDistinguishesLifecyclePauseFromModalDispatch() throws {
        let input = OriginalHuntSession.Input(destination: 3,month: 4,weatherCategory: 0,snow: false,
            mileage: 123,lastSuccessfulHuntMileage: 100,ammunition: 20,survivors: 5,currentFood: 0,
            foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: true,edition: .macintoshCD12,rain: 0)
        var tick = 10
        let random = OriginalRandomStream(seed: 999)
        let scene = try OriginalHuntScene(input: input,random: random,cdAssets: CDHuntSessionTests.assets(),clock: { tick }) { _ in }
        tick = 40; scene.setActive(true)
        #expect(scene.session.endTick == 1240)
        let seed = random.seed
        scene.setModalDispatchBlocked(true); tick = 100; scene.update(0)
        #expect(scene.session.endTick == 1240 && random.seed == seed && !scene.session.isPaused)
        scene.setModalDispatchBlocked(false)
        scene.setActive(false); tick = 200; scene.setActive(true)
        #expect(scene.session.endTick == 1340 && random.seed == seed)
    }

    @MainActor @Test func cdFrameDispatchAdvancesMoveAndHonorsModalAndInactiveGates() throws {
        let input = OriginalHuntSession.Input(destination: 3,month: 4,weatherCategory: 0,snow: false,
            mileage: 123,lastSuccessfulHuntMileage: 100,ammunition: 20,survivors: 5,currentFood: 0,
            foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: true,edition: .macintoshCD12)
        var tick = 10
        let scene = try OriginalHuntScene(input: input,random: OriginalRandomStream(seed: 999),
            cdAssets: CDHuntSessionTests.assets(),clock: { tick }) { _ in }
        scene.setActive(true)
        scene.move(); tick = 13; scene.advanceFrame(at: tick)
        #expect((scene.session as? CDHuntSession)?.view == 1)
        scene.setModalDispatchBlocked(true)
        scene.move(); tick = 16; scene.advanceFrame(at: tick)
        #expect((scene.session as? CDHuntSession)?.view == 1)
        scene.setModalDispatchBlocked(false)
        scene.setActive(false)
        scene.move(); tick = 19; scene.advanceFrame(at: tick)
        #expect((scene.session as? CDHuntSession)?.view == 1)
    }

    @Test(arguments: [GameEdition.macintosh11,.macintoshCD12])
    func settlementAcceptsOnlyTheJourneysEditionAndPreservesStartupCapacity(edition: GameEdition) throws {
        var trip = Journey(names: ["A","B"],seed: 1,edition: edition)
        trip.phase = .travel; trip.locationID = "kansas"; trip.destinationID = "big-blue"; trip.legDistance = 83
        trip.inventory[.food] = 1750; trip.inventory[.bullets] = 50; trip.miles = 123
        try JourneyEngine.beginHunt(&trip)
        trip.members[1].health = 0
        let limit = edition == .macintoshCD12 ? 250 : 200
        let invalid = OriginalHuntSession.Result(foodShot: 350,foodCarried: 0,shots: 1,lastSuccessfulHuntMileage: 0,
                                                carryLimit: edition == .macintoshCD12 ? 200 : 250)
        #expect(throws: GameRuleError.self) { try JourneyEngine.finishHunt(result: invalid,in: &trip) }
        #expect(trip.phase == .hunting && trip.inventory[.bullets] == 50)
        let valid = OriginalHuntSession.Result(foodShot: 350,foodCarried: 0,shots: 1,lastSuccessfulHuntMileage: 0,carryLimit: limit)
        let result = try JourneyEngine.finishHunt(result: valid,in: &trip)
        #expect(result.foodCarried == limit && result.carryLimit == limit)
        #expect(trip.inventory[.food] == 1750+limit && trip.inventory[.bullets] == 49)
        #expect(trip.original?.restDays == 1 && trip.original?.lastSuccessfulHuntMileage == 123)
    }
    @Test func directCDSettlementUsesSoloAllowanceAndCancellationChargesNothing() throws {
        var trip = Journey(names: ["A"],seed: 1,edition: .macintoshCD12)
        trip.phase = .travel; trip.locationID = "kansas"; trip.destinationID = "big-blue"; trip.legDistance = 83
        trip.inventory[.food] = 100; trip.inventory[.bullets] = 50
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.cancelHunt(&trip)
        #expect(trip.phase == .travel && trip.inventory[.food] == 100 && trip.inventory[.bullets] == 50)
        #expect(trip.original?.restDays == 0)
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.finishHunt(food: 500,shots: 1,in: &trip)
        #expect(trip.inventory[.food] == 225 && trip.inventory[.bullets] == 49)
    }
}
