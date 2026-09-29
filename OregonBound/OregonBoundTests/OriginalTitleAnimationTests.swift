import Testing
@testable import OregonBound

struct OriginalTitleAnimationTests {
    @Test func creationConsumesRandomInOriginalOrderAndUsesInitialFrames() {
        var spans: [Int] = []
        let animation = OriginalTitleAnimation { spans.append($0); return 0 }
        #expect(spans == [0,30,40,80,80,300,300,300,300,100,60])
        #expect(animation.states.map(\.frame) == [1,10,13,16,18,20,30,38,41,43,45])
        #expect(animation.drawCommands.map(\.frame) == [0,45,43,41,38,30,20,18,16,13,10,1])
        #expect(animation.drawCommands[0].x == 9)
        #expect(animation.drawCommands[0].y == 9)
        #expect(animation.drawCommands[0].width == 494)
        #expect(animation.drawCommands[0].height == 304)
    }

    @Test func loopPlaysThreeCyclesThenPauses() {
        var animation = OriginalTitleAnimation { _ in 0 }
        var frames: [Int] = []
        for update in 0..<41 {
            animation.step { _ in 0 }
            if update.isMultiple(of: 5) { frames.append(animation.states[1].frame) }
        }
        #expect(frames == [11,12,10,11,12,10,11,12,10])
        #expect(animation.states[1].delay == 40)
        #expect(animation.states[1].rate == 0)
        for _ in 0..<40 { animation.step { _ in 0 } }
        #expect(animation.states[1].frame == 10)
        animation.step { _ in 0 }
        #expect(animation.states[1].frame == 11)
    }

    @Test func pingpongInitialDelayAndRepeatLimit() {
        var animation = OriginalTitleAnimation { $0 == 100 ? 2 : 0 }
        var frames: [Int] = []
        for _ in 0..<8 {
            animation.step { $0 == 100 ? 7 : 0 }
            frames.append(animation.states[9].frame)
        }
        #expect(frames == [43,43,44,43,44,43,44,43])
        #expect(animation.states[9].delay == 47)
        #expect(animation.states[9].repeatsRemaining == 3)
    }

    @Test func slowFrameAdvancesImmediatelyThenHoldsForPeriod() {
        var animation = OriginalTitleAnimation { _ in 0 }
        animation.step { _ in 0 }
        #expect(animation.states[0].frame == 2)
        for _ in 0..<14 { animation.step { _ in 0 } }
        #expect(animation.states[0].frame == 2)
        animation.step { _ in 0 }
        #expect(animation.states[0].frame == 3)
    }
}
