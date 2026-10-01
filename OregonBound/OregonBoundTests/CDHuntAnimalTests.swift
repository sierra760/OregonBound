import Testing
@testable import OregonBound

struct CDHuntAnimalTests {
    typealias Rect = OriginalHuntSession.Rect
    private func animal(_ species: Int = 0, x: Int = 50, y: Int = 160, left: Bool = true) -> CDHuntAnimal {
        CDHuntAnimal(id: 1,species: species,depth: 1,x: x,y: y,fromLeft: left,
                     initialBounds: Rect(x: 0,y: 0,width: 40,height: 30),
                     frames: Array(repeating: Rect(x: 0,y: 0,width: 20,height: 15),count: 12))
    }
    private func rolls(_ values: [Int], run: ((Int)->Int)->Void) {
        var pending = values
        run { bound in
            let value = pending.removeFirst(); #expect(value < bound); return value
        }
        #expect(pending.isEmpty)
    }

    @Test func depthArtKeepsInitialBoundsUntilFirstFrameAdvance() {
        var value = animal(), timers = CDHuntAnimal.StopTimers()
        for tick in [0,3] {
            #expect(value.advance(tick: tick,startled: false,obstacles: [],timers: &timers,random: { _ in 99 }) == 0)
            #expect(value.rect.width == 40 && value.frame == 0)
            #expect(value.drawRect.width == 20 && value.drawRect.height == 15)
        }
        _ = value.advance(tick: 6,startled: false,obstacles: [],timers: &timers,random: { _ in 99 })
        #expect(value.frame == 1 && value.framePhase == 0)
        #expect(value.rect == Rect(x: 59,y: 160,width: 20,height: 15))
    }

    @Test func spontaneousStopsShareDeadlinesAndRetainAnimationPhase() {
        var value = animal(), timers = CDHuntAnimal.StopTimers()
        rolls([0,7,99]) { random in
            _ = value.advance(tick: 0,startled: false,obstacles: [],timers: &timers,random: random)
        }
        #expect(value.behavior == 2 && value.velocityX == 0 && value.frame == 6 && value.framePhase == 1)
        #expect(timers.movingPoseDeadline == 100)
        timers.movingPoseDeadline = 150 // Another animal's stop changed the shared timer.
        rolls([0,99]) { random in
            _ = value.advance(tick: 100,startled: false,obstacles: [],timers: &timers,random: random)
        }
        #expect(value.behavior == 2 && value.framePhase == 2)
        rolls([0,5,99]) { random in
            _ = value.advance(tick: 150,startled: false,obstacles: [],timers: &timers,random: random)
        }
        #expect(value.behavior == 1 && value.frame == 8 && timers.stillPoseDeadline == 255)
        rolls([99]) { random in
            _ = value.advance(tick: 153,startled: true,obstacles: [],timers: &timers,random: random)
        }
        #expect(value.behavior == 0 && value.velocityX == 3 && value.frame == 1)
        #expect(value.x == 53) // Callback restores motion before the same update's translation.
    }

    @Test func terrainFootStripStopsLargeAnimalsButLetsSmallAnimalsContinueOnZeroRoll() {
        let obstacle = TerrainExtractor.Obstacle(top: 188,left: 90,bottom: 200,right: 100)
        var value = animal(), timers = CDHuntAnimal.StopTimers()
        rolls([99,99,0,0]) { random in
            _ = value.advance(tick: 0,startled: false,obstacles: [obstacle],timers: &timers,random: random)
        }
        #expect(value.behavior == 2 && value.x == 50 && value.velocityX == 0)
        var rabbit = animal(2)
        rolls([99,0,0]) { random in
            _ = rabbit.advance(tick: 0,startled: false,obstacles: [obstacle],timers: &timers,random: random)
        }
        #expect(rabbit.velocityX == 9 && rabbit.x == 59 && rabbit.behavior == 0)
    }

    @Test func terrainTurnsGroundAnimalsButDoesNotTurnFlyingClasses() {
        let obstacle = TerrainExtractor.Obstacle(top: 188,left: 90,bottom: 200,right: 100)
        var value = animal(), timers = CDHuntAnimal.StopTimers()
        rolls([99,99,1]) { random in
            _ = value.advance(tick: 0,startled: false,obstacles: [obstacle],timers: &timers,random: random)
        }
        #expect(value.velocityX == -3 && value.mirrored && value.x == 47)
        var bird = animal(7)
        rolls([0,0]) { random in
            _ = bird.advance(tick: 0,startled: false,obstacles: [obstacle],timers: &timers,random: random)
        }
        #expect(bird.velocityX == 8 && !bird.mirrored)
    }

    @Test func groundDeathDecrementsOnceAndFinishesItsDeathFrames() {
        var value = animal(), timers = CDHuntAnimal.StopTimers()
        value.hit(atY: 190)
        #expect(value.advance(tick: 0,startled: false,obstacles: [],timers: &timers,random: { _ in Issue.record("Dead animal consumed randomness"); return 0 }) == -1)
        #expect(value.frame == 4 && value.velocityX == 0 && value.behavior == -1)
        var delta = 0
        for tick in stride(from: 3,through: 18,by: 3) {
            delta += value.advance(tick: tick,startled: false,obstacles: [],timers: &timers,random: { _ in 0 })
        }
        #expect(delta == 0 && value.frame == 5 && value.framePeriod == 0)
        #expect(value.x == 50 && value.y == 160)
    }

    @Test func fallingBirdRepeatsOriginalCounterDecrementAndRetainsHorizontalMotion() {
        var value = animal(7,y: 100), timers = CDHuntAnimal.StopTimers()
        value.hit(atY: 110) // Fall threshold max(229-110,110) = 119.
        var deltas: [Int] = []
        for tick in stride(from: 0,through: 18,by: 3) {
            deltas.append(value.advance(tick: tick,startled: true,obstacles: [],timers: &timers,random: { _ in 0 }))
        }
        #expect(deltas == [-1,-1,-1,-1,-1,-1,-1])
        #expect(value.y == 121 && value.x == 98 && value.velocityX == 0 && value.velocityY == 0)
        #expect(value.advance(tick: 21,startled: true,obstacles: [],timers: &timers,random: { _ in 0 }) == 0)
        #expect(value.frame == 11)
    }

    @Test func exitingAndSceneClearReportOriginalCounterChanges() {
        var value = animal(x: 503), timers = CDHuntAnimal.StopTimers()
        #expect(value.advance(tick: 0,startled: true,obstacles: [],timers: &timers,random: { _ in 99 }) == -1)
        #expect(value.deleted && value.x == 506)
        var corpse = animal(); corpse.hit(atY: 100)
        #expect(corpse.advance(tick: 0,startled: false,obstacles: [],clear: true,timers: &timers,random: { _ in 0 }) == -1)
        #expect(corpse.deleted)
    }
}
