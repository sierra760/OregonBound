import Testing
@testable import OregonBound

struct OriginalHuntSessionTests {
    typealias Hunt = OriginalHuntSession
    private func input(destination: Int = 2, month: Int = 4, snow: Bool = false) -> Hunt.Input {
        .init(destination: destination,month: month,weatherCategory: 0,snow: snow,mileage: 20,
              lastSuccessfulHuntMileage: 20,ammunition: 99,survivors: 5,currentFood: 0,
              foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: false)
    }
    private func session(_ value: Hunt.Input? = nil) -> Hunt {
        var random = OriginalRandom(seed: 1234)
        return Hunt(input: value ?? input(),startTick: 0) { random.bounded($0) }
    }
    private func buffaloSession() -> Hunt {
        var removals = [2,3]
        return Hunt(input: input(),startTick: 0) { bound in bound == 7 ? removals.removeFirst() : 0 }
    }
    private func spawnBuffalo(_ hunt: inout Hunt) {
        var rolls = [7,35,0,0,99]
        hunt.advance(to: 0) { bound in
            let value = rolls.removeFirst(); #expect(value < bound); return value
        }
        #expect(rolls.isEmpty)
    }
    private func quiet(_ bound: Int) -> Int { bound == 270 ? 0 : max(0,bound-1) }

    @Test func inputViewportUsesSourceUserItemEdges() {
        // DITL9160 item3 is local(0,0,494,262), installed in pane13 at(9,9).
        // OriginalHuntScene filters mouse/touch dispatch using this predicate;
        // the original projectile routine itself receives an already-filtered point.
        for (x,y,expected) in [(9,8,false), (9,9,true),
                              (502,9,true), (503,9,false),
                              (9,270,true), (502,270,true),
                              (9,271,false), (8,100,false)] {
            #expect(Hunt.viewport.contains(x: x,y: y) == expected, "Input at (\(x),\(y))")
        }
    }

    @Test func skyFillCopiesUserItemTopAndSetsAbsoluteBottom34() {
        let h = session()
        #expect(h.fillCommands[0].rect == Hunt.Rect(x: 9,y: 9,width: 494,height: 25))
        #expect(h.fillCommands[1].rect == Hunt.Rect(x: 9,y: 59,width: 494,height: 175))
    }

    @Test func settlementAndOriginalResultText() {
        var value = input()
        value.mileage = 25
        value.currentFood = 2000
        let full = Hunt.settle(foodShot: 250, shots: 1, input: value)
        #expect(full.foodCarried == 0)
        #expect(full.lastSuccessfulHuntMileage == 25) // Updated before wagon-capacity clamp.
        #expect(full.message == "You shot 250 pound(s) of food using 1 bullet(s), but were only able to fit 0 more pound(s) of food in your wagon.  If you continue to hunt in this area, game will become scarce.")
        value.currentFood = 0
        let carry = Hunt.settle(foodShot: 250, shots: 1, input: value)
        #expect(carry.foodCarried == 200)
        #expect(carry.message.contains("only able to carry 200"))
        let small = Hunt.settle(foodShot: 5, shots: 2, input: value)
        #expect(small.message.hasPrefix("You brought back 5 pound(s) of food and used 2 bullet(s)."))
        let empty = Hunt.settle(foodShot: 0, shots: 0, input: value)
        #expect(empty.lastSuccessfulHuntMileage == 20)
        #expect(empty.message.hasSuffix("game will become scarce."))
        value.survivors = 1
        #expect(Hunt.settle(foodShot: 250, shots: 1, input: value).foodCarried == 100)
    }

    @Test func originalTablesAndPaletteSelectors() {
        #expect(Hunt.initialWeights(destination: 6,month: 4,repeated: false) == [15,25,40,40,15,5,20])
        #expect(Hunt.initialWeights(destination: 13,month: 10,repeated: true) == [8,10,20,20,8,10,0])
        #expect(Hunt.palette(destination: 4,month: 5,weather: 0,snow: false).groundIndex == 86)
        #expect(Hunt.palette(destination: 3,month: 5,weather: 2,snow: false).skyIndex == 196)
        #expect(Hunt.palette(destination: 6,month: 6,weather: 0,snow: false).groundIndex == 86)
        #expect(Hunt.palette(destination: 15,month: 3,weather: 0,snow: false).groundIndex == 166)
        #expect(Hunt.palette(destination: 2,month: 5,weather: 0,snow: true).groundIndex == 0)
    }

    @Test func sceneryFlagsFramesAndRandomCounts() {
        for d in -1...16 {
            for snow in [false,true] {
                var h = session(input(destination: d,snow: snow))
                h.advance(to: 0,random: quiet)
                let frames = h.objects.filter { $0.role == .scenery }.map(\.frame)
                #expect(!frames.isEmpty)
                #expect(h.objects.filter { $0.role == .scenery }.allSatisfy { $0.category == 2 })
                let shifted = frames.map { $0-(snow ? 8 : 0) }
                if d == 4 { #expect(shifted.allSatisfy { [4,5].contains($0) }); #expect((4...6).contains(frames.count)) }
                else if d <= 4 { #expect(shifted.allSatisfy { [4,5,7].contains($0) }) }
                else { #expect(shifted.allSatisfy { [4,5,9,10,11].contains($0) }) }
                #expect(h.objects.filter { $0.role == .scenery }.allSatisfy {
                    $0.rect.x >= 9 && $0.rect.right < 503 && $0.rect.y >= 59 && $0.rect.bottom < 225
                })
            }
        }
    }

    @Test func spawnAndProjectileUseOriginalUpdateOrderAndLatency() {
        var h = buffaloSession()
        #expect(h.population == [15,25,0,0,0,0,0])
        spawnBuffalo(&h)
        let animal = h.objects.first { $0.role == .animal(0) }!
        #expect(animal.rect.x == 500 && animal.rect.y == 59 && animal.mirrored)
        #expect(h.shoot(x: 470,y: 75) == .fired)
        #expect(h.projectile?.remaining == 10)
        #expect(h.shoot(x: 470,y: 75) == .inFlight)
        for tick in stride(from: 3,through: 30,by: 3) { h.advance(to: tick,random: quiet) }
        #expect(h.foodShot == 0 && h.projectile?.remaining == 0)
        h.advance(to: 33,random: quiet)
        #expect(h.foodShot == 250 && h.projectile == nil && h.shots == 1)
        #expect(h.sceneKills == 1 && h.liveAnimals == 0)
        #expect(h.population == [8,25,0,0,0,0,0])
        #expect(h.takeEvents().contains(.hit(species: 0,food: 250)))
        for tick in stride(from: 36,through: 60,by: 3) { h.advance(to: tick,random: quiet) }
        let dead = h.objects.first { $0.role == .animal(0) }!
        #expect(dead.frame == 5 && dead.framePeriod == 0 && dead.velocity == 0)
        h.stop(); h.advance(to: 63,random: quiet)
        #expect(h.result?.foodCarried == 200 && h.result?.shots == 1)
    }

    @Test func sceneryBlocksProjectileRectEvenWhenItsArtMayBeTransparent() {
        var h = buffaloSession()
        h.advance(to: 0,random: quiet)
        let scenery = h.objects.first { $0.role == .scenery }!
        #expect(h.shoot(x: scenery.rect.x,y: scenery.rect.y) == .fired)
        let duration = h.projectile!.remaining
        for n in 1...(duration+1) { h.advance(to: n*3,random: quiet) }
        #expect(h.takeEvents().contains(.blocked))
        #expect(h.foodShot == 0)
    }

    @Test func moveClearsShotAndSceneWithoutResettingHuntCountersOrDeadline() {
        var h = buffaloSession(); spawnBuffalo(&h)
        let end = h.endTick
        let oldIDs = Set(h.objects.filter { $0.role == .scenery || $0.role == .animal(0) }.map(\.id))
        h.shoot(x: 450,y: 90); h.move(); h.advance(to: 3,random: quiet)
        #expect(h.shots == 1 && h.endTick == end && h.sceneKills == 0 && h.liveAnimals == 0)
        #expect(h.projectile == nil && Set(h.objects.map(\.id)).isDisjoint(with: oldIDs))
        #expect(h.objects.filter { $0.role == .scenery }.allSatisfy { $0.visible })
    }

    @Test func ammoCapDoesNotEndHuntAndStopSettlesOnce() {
        var h = session()
        for n in 0..<20 {
            #expect(h.shoot(x: 256,y: 228) == .fired)
            h.advance(to: n*3,random: quiet)
        }
        #expect(h.shots == 20 && h.ammunitionRemaining == 0 && !h.isComplete)
        #expect(h.shoot(x: 256,y: 228) == .noAmmunition)
        h.stop(); h.advance(to: 60,random: quiet)
        #expect(h.isComplete && h.result?.shots == 20)
        _ = h.takeEvents(); h.advance(to: 63,random: quiet)
        #expect(h.takeEvents().isEmpty)
    }

    @Test func deadlinesNoCatchupAndNativeLifecyclePause() {
        var h = session(); let initialObjects = h.objects
        h.setPaused(true,at: 10); h.advance(to: 500) { _ in Issue.record("Paused RNG call"); return 0 }
        #expect(h.objects == initialObjects)
        h.setPaused(false,at: 510); #expect(h.endTick == 1700)
        h.advance(to: 1000,random: quiet); #expect(h.nextTick == 1003)
        h.advance(to: 1002) { _ in Issue.record("Premature RNG call"); return 0 }
        h.advance(to: 1701,random: quiet); #expect(!h.isComplete)
        h.advance(to: 1704,random: quiet); #expect(h.isComplete)
    }
    @Test func completeSeededHuntsMaintainSceneAndAmmoInvariants() {
        for destination in [1,4,6,13,15] {
            var random = OriginalRandom(seed: UInt32(100+destination))
            var h = Hunt(input: input(destination: destination),startTick: 0) { random.bounded($0) }
            for tick in stride(from: 0,through: 1230,by: 3) {
                if tick % 90 == 0 { h.move() }
                if let animal = h.objects.first(where: { $0.category < 0 }) {
                    h.shoot(x: animal.rect.x+animal.rect.width/2,y: animal.rect.y+animal.rect.height/2)
                }
                h.advance(to: tick) { random.bounded($0) }
                #expect((0...2).contains(h.liveAnimals))
                #expect(h.sceneKills <= 4 && h.shots <= 20)
                #expect(h.population.allSatisfy { $0 >= 0 })
            }
            #expect(h.isComplete)
            #expect((h.result?.foodCarried ?? 0) <= 200)
        }
    }

}
