import Testing
@testable import OregonBound

struct OriginalAudioBackendTests {
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
