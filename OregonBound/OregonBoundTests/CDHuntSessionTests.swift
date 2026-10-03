import Testing
@testable import OregonBound

struct CDHuntSessionTests {
    typealias Rect = OriginalHuntSession.Rect
    static func assets(left: Bool = true, right: Bool = true) -> CDHuntAssets {
        var frames: [Int: [Rect]] = [19160: Array(repeating: Rect(x: 0,y: 0,width: 1,height: 1),count: 20)]
        frames[19160]![3] = Rect(x: 0,y: 0,width: 5,height: 5)
        var terrains: [Int: TerrainExtractor.Terrain] = [:]
        for habitat in 0..<10 {
            for view in 0..<3 {
                let id = 19200+10*habitat+view
                terrains[id] = .init(resourceID: id,leftEntryAllowed: left,rightEntryAllowed: right,obstacles: [])
                for snow in [0,3] { frames[id+snow] = [Rect(x: 0,y: 0,width: 494,height: 259)] }
            }
        }
        for species in 0..<11 {
            for depth in (species == 10 ? [0] : [0,1,2]) {
                let resource = 19161+species+[0,200,300][depth]
                frames[resource] = Array(repeating: Rect(x: 0,y: 0,width: 40-depth*10,height: 30-depth*5),
                                         count: CDHuntAnimal.profiles[species].lastFrame+1)
            }
        }
        return CDHuntAssets(frames: frames,terrains: terrains,monochrome: false)
    }
    private func input(survivors: Int = 5, snow: Bool = false) -> OriginalHuntSession.Input {
        .init(destination: 2,month: 4,weatherCategory: 0,snow: snow,mileage: 123,lastSuccessfulHuntMileage: 100,
              ammunition: 20,survivors: survivors,currentFood: 0,foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: true)
    }
    private func session(species: Int = 0, assets: CDHuntAssets? = nil, snow: Bool = false) -> CDHuntSession {
        var weights = Array(repeating: 0,count: 11); weights[species] = 20
        return CDHuntSession(input: input(snow: snow),preparation: .init(habitat: 1,population: weights),
                             assets: assets ?? Self.assets(),startTick: 0,random: { _ in 0 })
    }
    private func rolls(_ values: [Int], run: ((Int)->Int)->Void) {
        var pending = values
        run { bound in
            let value = pending.removeFirst(); #expect(value < bound); return value
        }
        #expect(pending.isEmpty)
    }
    @Test func groundSpawnUsesSidePermissionsDepthAndFiveLiveCap() {
        var hunt = session(assets: Self.assets(left: false,right: true))
        for n in 0..<5 {
            // Spawn roll, weighted choice, requested left entry (forced right), ground y,
            // then two behavioral rolls per current animal.
            rolls([7,0,1,0]+Array(repeating: 99,count: 2*(n+1))) { random in hunt.advance(to: n*3,random: random) }
        }
        #expect(hunt.animals.count == 5 && hunt.liveAnimals == 5)
        #expect(hunt.animals.allSatisfy { $0.depth == 2 && $0.mirrored && $0.velocityX == -3 })
        rolls([7]+Array(repeating: 99,count: 10)) { random in hunt.advance(to: 15,random: random) }
        #expect(hunt.animals.count == 5)
    }
    @Test func flyingSpawnStillConsumesGroundHeightRollBeforeAirHeight() {
        var hunt = session(species: 7)
        rolls([7,0,0,70,40,99,99]) { random in hunt.advance(to: 0,random: random) }
        let bird = hunt.animals[0]
        #expect(bird.y == 54 && bird.depth == 1 && bird.x == 495)
        #expect(bird.resource == 19368)
    }
    @Test func moveCyclesTerrainAndSnowBackgroundWithoutResettingHuntDeadline() {
        var hunt = session(snow: true)
        #expect(hunt.backgroundResource == 19213 && hunt.terrain.resourceID == 19210)
        for expected in [1,2,0] {
            hunt.move()
            rolls([0,0,0,0]) { random in hunt.advance(to: hunt.nextTick,random: random) }
            #expect(hunt.view == expected && hunt.terrain.resourceID == 19210+expected)
            #expect(hunt.backgroundResource == 19213+expected && hunt.endTick == 1200)
        }
    }
    @Test func everyAcceptedClickStartlesEvenDuringFlightAndWithoutAmmo() {
        var hunt = session()
        #expect(hunt.shoot(x: 500,y: 100,at: 10) == .fired)
        #expect(hunt.shoot(x: 500,y: 100,at: 20) == .inFlight)
        #expect(hunt.startledUntil == 320 && hunt.shots == 1)
        var noAmmo = input(); noAmmo.ammunition = 0
        var empty = CDHuntSession(input: noAmmo,preparation: .init(habitat: 1,population: [20]+Array(repeating: 0,count: 10)),
                                  assets: Self.assets(),startTick: 0,random: { _ in 0 })
        #expect(empty.shoot(x: 100,y: 100,at: 30) == .noAmmunition)
        #expect(empty.startledUntil == 330 && empty.takeEvents() == [.dryFire])
    }
    @Test func stopAndTimeoutSettleCDCarryAllowances() {
        #expect(CDHuntSession.settle(foodShot: 500,shots: 2,input: input()).foodCarried == 250)
        #expect(CDHuntSession.settle(foodShot: 500,shots: 2,input: input(survivors: 1)).foodCarried == 125)
        var full = input(); full.currentFood = 1999
        let result = CDHuntSession.settle(foodShot: 500,shots: 2,input: full)
        #expect(result.foodCarried == 1 && result.carryLimit == 250 && result.lastSuccessfulHuntMileage == 123)
        var hunt = session(); hunt.advance(to: 1201,random: { _ in 0 })
        #expect(!hunt.isComplete)
        hunt.advance(to: 1204,random: { _ in 0 })
        #expect(hunt.result?.carryLimit == 250 && hunt.result?.shots == 0)
    }
    @Test func lifecyclePauseShiftsStopTimersAndDeadlineButModalGapsDoNotCatchUp() {
        var hunt = session(); hunt.setPaused(true,at: 1)
        hunt.advance(to: 300,random: { _ in Issue.record("Paused session consumed randomness"); return 0 })
        hunt.setPaused(false,at: 301)
        #expect(hunt.endTick == 1500)
        rolls([0]) { random in hunt.advance(to: 1000,random: random) }
        #expect(hunt.nextTick == 1003)
    }
    @Test func projectileHitsInLinkedListOrderAndSettlesExactlyOnce() {
        var hunt = session()
        rolls([7,0,0,70,99,99]) { random in hunt.advance(to: 0,random: random) }
        for tick in stride(from: 3,through: 240,by: 3) { hunt.advance(to: tick,random: { max(0,$0-1) }) }
        #expect(hunt.animals[0].x == 260)
        #expect(hunt.shoot(x: 260,y: 210,at: 241) == .fired)
        // This aim is within20 pixels of the muzzle, so impact is on the next callback.
        #expect(hunt.projectile?.remaining == 0)
        rolls([49,99,0]) { random in hunt.advance(to: 243,random: random) }
        #expect(hunt.foodShot == 250 && hunt.sceneKills == 1 && hunt.population[0] == 10)
        #expect(hunt.animals[0].dead && hunt.liveAnimals == 1)
        // Animal precedes projectile; its death callback runs on the following update.
        rolls([49]) { random in hunt.advance(to: 246,random: random) }
        #expect(hunt.liveAnimals == 0)
        hunt.stop(); hunt.advance(to: 249,random: { _ in 0 })
        #expect(hunt.result?.foodCarried == 250 && hunt.result?.shots == 1)
        #expect(hunt.takeEvents() == [.fired,.hit(species: 0,food: 250),.finished(hunt.result!)])
        hunt.advance(to: 10000,random: { _ in Issue.record("Completed hunt consumed randomness"); return 0 })
        #expect(hunt.takeEvents().isEmpty)
    }

    @Test func timeoutWaitsForTheProjectileAndMoveClearsIt() {
        var hunt = session()
        hunt.shoot(x: 500,y: 100,at: 1199)
        for tick in stride(from: 1201,through: 1237,by: 3) { hunt.advance(to: tick,random: { _ in 0 }) }
        #expect(hunt.projectile == nil && !hunt.isComplete)
        hunt.advance(to: 1240,random: { _ in 0 })
        #expect(!hunt.isComplete)
        hunt.advance(to: 1243,random: { _ in 0 })
        #expect(hunt.isComplete)
        var moving = session(); moving.shoot(x: 500,y: 100,at: 0); moving.move()
        rolls([0,0,0,0]) { random in moving.advance(to: 0,random: random) }
        #expect(moving.projectile == nil && moving.shots == 1 && moving.view == 1)
    }

}
