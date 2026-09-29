import Testing
@testable import OregonBound

struct OriginalAudioQueueTests {
    @Test func callbackDoesNotStartNextSoundUntilIdlePump() {
        var queue = OriginalAudioQueue()
        #expect(queue.request(9007) == [.start(9007)])
        queue.enqueue(9002)
        #expect(queue.request(9003).isEmpty)
        #expect(queue.pending == [9002,9003])
        #expect(queue.pump().isEmpty)
        queue.completed()
        #expect(queue.current == 9007)
        #expect(queue.pump() == [.stop,.start(9002)])
        #expect(queue.pending == [9003])
    }
    @Test func capacityAndHuntingInterruptionPreserveOriginalQueueOrder() {
        var queue = OriginalAudioQueue()
        _ = queue.request(9001)
        for id in 1...10 { queue.enqueue(id) }
        #expect(queue.pending == Array(1...8))
        #expect(queue.clear() == [.stop])
        queue.enqueue(9002)
        #expect(queue.current == nil)
        #expect(queue.pump() == [.start(9002)])
        #expect(queue.clear() == [.stop])
        queue.enqueue(9003)
        #expect(queue.pump() == [.start(9003)])
    }
    @Test func soundOffStopsClearsAndConsumesMutedEnqueues() {
        var queue = OriginalAudioQueue()
        _ = queue.request(9001); queue.enqueue(9002)
        #expect(queue.setEnabled(false) == [.stop])
        #expect(!queue.enabled && queue.current == nil && queue.pending.isEmpty)
        #expect(queue.request(9003).isEmpty)
        queue.enqueue(9003); queue.enqueue(9004)
        #expect(queue.pump().isEmpty && queue.pending == [9004])
        #expect(queue.setEnabled(true).isEmpty)
        #expect(queue.pump() == [.start(9004)])
    }
}
