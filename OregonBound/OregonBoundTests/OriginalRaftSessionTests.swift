import Testing
@testable import OregonBound

struct OriginalRaftSessionTests {

    @Test func cdRaftAudioFollowsIdleAndLogicalRedrawBeforeMovement() {
        for busy in [false, true] {
            for drowned in [false, true] {
                #expect(CDRaftAudio.idle(pauseSteps: 0, busy: busy, hasDrowned: drowned) == (busy ? [] : [.start(4006)]))
                #expect(CDRaftAudio.idle(pauseSteps: 100, busy: busy, hasDrowned: drowned) == (drowned ? [.start(4001)] : []))
                for pause in [-1, 1, 2, 99] {
                    #expect(CDRaftAudio.idle(pauseSteps: pause, busy: busy, hasDrowned: drowned).isEmpty)
                }
                #expect(CDRaftAudio.redrawLoss(hasDrowned: drowned) == (drowned ? [.start(4001)] : []))
            }
        }
        #expect(CDRaftAudio.collision == [.stop, .start(9006)])
    }
    @Test(arguments: [1, 4, 8])
    func cdDepthSelectsAuthoredRaftGeometryAndSourceProgressRate(depth: Int) throws {
        var value = input
        value.inventory.append(0)
        value.pixelDepth = depth
        var progressRolls = 0
        var laneDraw = 0
        func random(_ bound: Int) -> Int {
            if bound == 40 { progressRolls += 1; return 39 }
            // Source lanes must differ by at least15. Rolls0/3 give23/2,
            // keeping both rocks on the right and allowing the initial retry.
            laneDraw += 1
            return laneDraw.isMultiple(of: 2) ? 3 : 0
        }
        var session = OriginalRaftSession(input: value, startTick: 0, edition: .macintoshCD12, random: random)
        for command in session.drawCommands {
            #expect((depth == 1 ? [10000,10001] : [20000,20001]).contains(command.resource))
            if command.id == -3 { #expect(command.height == (depth == 1 ? 51 : 52)) }
        }
        #expect(session.drawCommands.first { $0.id == -1 }?.mirrored == true)
        session.advance(to: 0, mouseX: 0, random: random)
        #expect(session.remaining == (depth == 1 ? 1339 : 1338))
        #expect(session.nextTick == 3)
        for tick in stride(from: 3, through: 4500, by: 3) where !session.isComplete {
            session.advance(to: tick, mouseX: 0, random: random)
        }
        let result = try #require(session.result)
        #expect(result.remainingInventory == value.inventory && result.drownedMembers.isEmpty)
        #expect(progressRolls == (depth == 1 ? 1340 : 670))
    }

    private var input: OriginalRaftSession.Input {
        .init(inventory: [3,10,100,1,1,1,1000],living: [true,true,true],names: ["A","B","C"],rain: 400)
    }
    @Test func cdUsesRaftResourcesWithoutChangingGeometryOrMotion() {
        var classicRandom = OriginalRandom(seed: 1234)
        var cdRandom = OriginalRandom(seed: 1234)
        var classic = OriginalRaftSession(input: input, startTick: 0) { classicRandom.bounded($0) }
        var cdInput = input; cdInput.inventory.append(0)
        var cd = OriginalRaftSession(input: cdInput, startTick: 0, edition: .macintoshCD12) { cdRandom.bounded($0) }
        for tick in stride(from: 0, through: 300, by: 3) {
            #expect(cd.drawCommands.map(\.resource) == classic.drawCommands.map { $0.resource == 19200 ? 20000 : 20001 })
            for (a, b) in zip(classic.drawCommands, cd.drawCommands) {
                #expect(a.frame == b.frame && a.x == b.x && a.y == b.y)
                #expect(a.width == b.width && a.height == b.height)
                #expect(a.masked == b.masked && a.mirrored == b.mirrored)
            }
            classic.advance(to: tick, mouseX: 150) { classicRandom.bounded($0) }
            cd.advance(to: tick, mouseX: 150) { cdRandom.bounded($0) }
        }
        #expect(cd.remaining == classic.remaining)
        #expect(cdRandom.seed == classicRandom.seed)
    }

    @Test func initialLaneSentinelRetriesAndIsResetAfterInitialRock() {
        var values = [0,4]
        var bounds: [Int] = []
        let session = OriginalRaftSession(input: input,startTick: 0) { bounds.append($0); return values.removeFirst() }
        #expect(bounds == [8,8]); #expect(session.rocks.first?.lane == -5)
        #expect(session.rocks.first?.x == 179); #expect(session.rocks.first?.y == 39)
    }
    @Test func progressAndDeadlineDoNotCatchUpAndPauseHasNoRandomDraws() {
        var draws = 0
        var session = OriginalRaftSession(input: input,startTick: 10) { _ in defer { draws += 1 }; return draws == 0 ? 0 : 4 }
        session.advance(to: 9,mouseX: 100) { _ in Issue.record("Too early"); return 0 }
        #expect(session.remaining == 1340)
        session.advance(to: 1000,mouseX: 100) { _ in 39 }
        #expect(session.remaining == 1338); #expect(session.raftLeft == 155)
        session.setPaused(true,at: 1000)
        session.advance(to: 9999,mouseX: nil) { _ in Issue.record("Paused draw"); return 0 }
        #expect(session.remaining == 1338)
    }
    @Test func clampPreservesOriginalLogicalVersusSpriteOffset() {
        var n = 0
        var session = OriginalRaftSession(input: input,startTick: 0) { _ in defer { n += 1 }; return n == 0 ? 0 : 4 }
        for tick in stride(from: 0,through: 114,by: 3) { session.advance(to: tick,mouseX: 0) { _ in 39 } }
        #expect(session.raftLeft == 10); #expect(session.raftSpriteLeft == 11)
        #expect(session.direction == 0)
        session.advance(to: 117,mouseX: 400) { _ in 39 }
        #expect(session.raftLeft == 14); #expect(session.raftSpriteLeft == 15)
    }
    @Test func trajectoryUsesSingleStorageAndFrameBeforeMove() {
        var n = 0
        var session = OriginalRaftSession(input: input,startTick: 0) { _ in defer { n += 1 }; return n == 0 ? 0 : 4 }
        for tick in stride(from: 0,through: 36,by: 3) { session.advance(to: tick,mouseX: nil) { _ in 39 } }
        #expect(session.rocks.first?.y == 65)
        #expect(session.rocks.first?.frame == 10) // callback saw63
        #expect(session.rocks.first?.x == 177) // 13×−0.178 crosses−2 once
        session.advance(to: 39,mouseX: nil) { _ in 39 }
        #expect(session.rocks.first?.frame == 8) // callback saw65
    }
    @Test func positiveIntersectionAndFrameThresholds() {
        #expect(!OriginalRaftSession.hits(rockX: 111,rockY: 189,raftLeft: 159,direction: 0))
        #expect(OriginalRaftSession.hits(rockX: 112,rockY: 189,raftLeft: 159,direction: 0))
        #expect(OriginalRaftSession.rockFrame(top: 63) == 10)
        #expect(OriginalRaftSession.rockFrame(top: 64) == 8)
    }
    @Test func collisionExactRNGOrderRawOxenAndLeaderLast() {
        var n = 0
        var session = OriginalRaftSession(input: input,startTick: 0) { _ in defer { n += 1 }; return n == 0 ? 0 : 4 }
        var bounds: [Int] = []
        for tick in stride(from: 0,through: 300,by: 3) {
            session.advance(to: tick,mouseX: nil) { bound in
                bounds.append(bound)
                return bound == 40 ? 39 : 0
            }
            if session.collision != nil { break }
        }
        #expect(session.collision != nil)
        #expect(Array(bounds.suffix(17)) == [100,11,100,101,100,2,100,2,100,2,100,1001,100,100,100,100,100])
        #expect(session.inventory[0] == 0)
        #expect(session.collision?.drownedMembers == [1,2,0])
        #expect(session.pauseSteps == 100)
        session.advance(to: session.nextTick,mouseX: nil) { _ in Issue.record("Pause draw"); return 0 }
        #expect(session.pauseSteps == 98)
        session.dismissCollision()
        session.advance(to: session.nextTick,mouseX: nil) { _ in Issue.record("Finish draw"); return 0 }
        #expect(session.result?.survivors == 0)
        #expect(session.result?.losses == [3,0,0,0,0,0,0])
        #expect(session.result?.drownedMembers == [0,1,2])
    }
    @Test func rainCapAndMapTruncation() {
        #expect(OriginalRaftSession.markerTarget(progress: 18) == Float(467))
        #expect(Int(Double(OriginalRaftSession.markerTarget(progress: 116))-475) == 0)
        var n = 0
        var p = input; p.rain = 850
        let session = OriginalRaftSession(input: p,startTick: 0) { _ in defer { n += 1 }; return n == 0 ? 0 : 4 }
        #expect(session.maximumRocks == 1)
    }
    @Test func cdCollisionDrawsAndLosesPerishableFoodBeforePeople() {
        let cdInput = OriginalRaftSession.Input(inventory: [0,0,0,0,0,0,0,100],
                                                living: [true], names: ["A"], rain: 400)
        var startup = [0,4]
        var session = OriginalRaftSession(input: cdInput, startTick: 0, edition: .macintoshCD12) { _ in startup.removeFirst() }
        var bounds: [Int] = []
        for tick in stride(from: 0, through: 300, by: 3) {
            session.advance(to: tick, mouseX: nil) { bound in
                bounds.append(bound)
                return bound == 40 ? 39 : bound == 101 ? 25 : 0
            }
            if session.collision != nil { break }
        }
        #expect(session.collision?.losses == [0,0,0,0,0,0,0,25])
        #expect(session.inventory[7] == 75)
        #expect(Array(bounds.suffix(3)) == [100,101,100])
        #expect(session.collision?.drownedMembers == [0])
    }

}
