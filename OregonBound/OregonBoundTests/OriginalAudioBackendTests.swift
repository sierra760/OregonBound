import Testing
@testable import OregonBound

struct OriginalAudioBackendTests {

    @MainActor @Test(arguments: [0, 1, 2])
    func cdRiverScenePlaysSourceTimelineAndClosesBeforeResult(failure: Int) {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let scene = OriginalRiverScene(audio: audio)
        var resultCount = 0
        scene.start(animation: Self.riverAnimation(), failureKind: failure, edition: .macintoshCD12) {
            resultCount += 1
            #expect(!audio.isPlaying)
            audio.request(9001)
        }
        scene.setActive(true)
        for counter in 0..<8 { scene.advance(to: UInt64(counter * 3)) }
        #expect(output.started.isEmpty)
        scene.advance(to: 24)
        #expect(output.started == [4008])
        scene.advance(to: 24) // One update per three ticks, even if called twice.
        scene.setActive(false); scene.advance(to: 1000)
        scene.setActive(true)
        scene.setModalDispatchBlocked(true); scene.advance(to: 2000)
        scene.setModalDispatchBlocked(false)
        #expect(output.started == [4008])
        for counter in 9...16 { scene.advance(to: UInt64(2000 + counter * 3)) }
        #expect(output.started == [4008]) // Busy channel prevents ambience.
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        scene.advance(to: 2051)
        #expect(output.started == [4008, 4009])
        for counter in 18...150 { scene.advance(to: UInt64(2000 + counter * 3)) }
        #expect(output.started == [4008, 4009, failure == 0 ? 4010 : 4014])
        for counter in 151...180 { scene.advance(to: UInt64(2000 + counter * 3)) }
        #expect(resultCount == 1 && output.started.last == 9001)
        let stops = output.stops
        scene.close(); scene.close(); scene.advance(to: 9000)
        #expect(output.stops == stops && audio.isPlaying && resultCount == 1)
    }

    @MainActor @Test func riverCloseRestartMuteAndClassicIsolation() {
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let scene = OriginalRiverScene(audio: audio)
        audio.request(6001)
        scene.close()
        #expect(output.stops == 0)
        scene.start(animation: Self.riverAnimation(), failureKind: 0, edition: .macintosh11) {}
        scene.setActive(true)
        for counter in 0...180 { scene.advance(to: UInt64(counter * 3)) }
        scene.close()
        #expect(output.started == [6001] && output.stops == 0)
        scene.start(animation: Self.riverAnimation(), failureKind: 2, edition: .macintoshCD12) {}
        #expect(output.stops == 0)
        scene.close()
        #expect(output.stops == 1)
        scene.start(animation: Self.riverAnimation(), failureKind: 2, edition: .macintoshCD12) {}
        scene.setActive(true)
        audio.enabled = false
        for counter in 0...180 { scene.advance(to: UInt64(counter * 3)) }
        #expect(output.started == [6001])
    }

    private static func riverAnimation() -> OriginalRiverAnimation {
        var animation = OriginalRiverAnimation(programs: [[
            .init(offset: 0, size: 4, opcode: 1, arguments: [170]),
            .init(offset: 4, size: 2, opcode: 255, arguments: [])
        ]], creationOrder: [0])
        animation.step() // Match the nondrawing source initialization.
        return animation
    }
    @Test func sessionResetDiscardsOldWaitersCallbacksAndPumps() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        audio.request(9002); audio.enqueue(9003)
        var oldWaiter = false
        audio.waitUntilIdle { oldWaiter = true }
        let oldCallback = output.callbacks[0], oldPump = idle.removeFirst()
        audio.resetForSession()
        #expect(audio.enabled)
        audio.enqueue(6001)
        oldCallback(); oldPump()
        #expect(output.started == [9002])
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9002, 6001])
        #expect(!oldWaiter)
    }
    final class Output: OriginalAudioPlayback {
        var started: [Int] = []
        var callbacks: [() -> Void] = []
        var stops = 0
        var succeeds = true
        func start(_ resource: Int, completion: @escaping () -> Void) -> Bool {
            started.append(resource);callbacks.append(completion);return succeeds
        }
        func stop() { stops += 1 }
    }
    @Test func staleNativeCallbackCannotCompleteReplacementSound() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output,scheduleIdle: { idle.append($0) })
        audio.request(9002)
        #expect(output.started == [9002])
        guard let oldCompletion = output.callbacks.first else { return }
        audio.clear();audio.request(9003);audio.enqueue(9004)
        oldCompletion()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9002,9003])
        #expect(output.stops == 1)
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9002,9003,9004])
    }
    @Test func cleanupWaitsForNativeCompletionInsteadOfDiscardingLastSound() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output,scheduleIdle: { idle.append($0) })
        audio.request(9003)
        var finished = false
        audio.waitUntilIdle { finished = true }
        #expect(!finished)
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(finished)
    }
    @Test func muteImmediatelyStopsOutputAndFailedStartClearsPending() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output,scheduleIdle: { idle.append($0) })
        audio.request(9002);audio.enqueue(9003);audio.enabled = false
        #expect(output.stops == 1)
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9002])
        audio.enabled = true;output.succeeds = false
        audio.enqueue(9003);audio.enqueue(9004)
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9002,9003])
    }
}
