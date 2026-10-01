import Testing
import Foundation
@testable import OregonBound

struct OriginalAudioBackendTests {

    @MainActor @Test func cdRaftAmbienceChecksIdleBeforeMovementDeadline() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let random = OriginalRandomStream(seed: 77)
        let scene = OriginalRaftScene(session: Self.raftSession(), random: random, audio: audio, clock: { 0 }) { _ in }
        scene.setActive(true)
        scene.advance(to: 0, mouseX: nil)
        #expect(output.started == [4006])
        let remaining = scene.session.remaining, seed = random.seed
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        scene.advance(to: 1, mouseX: nil)
        #expect(output.started == [4006, 4006])
        #expect(scene.session.remaining == remaining && random.seed == seed)
        scene.setModalDispatchBlocked(true)
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        scene.advance(to: 2, mouseX: nil)
        #expect(output.started.count == 2)
        scene.setModalDispatchBlocked(false)
        scene.setActive(false); scene.advance(to: 2, mouseX: nil)
        #expect(output.started.count == 2)
        scene.setActive(true)
        audio.enabled = false; scene.advance(to: 2, mouseX: nil)
        #expect(output.started.count == 2)
        audio.enabled = true; scene.advance(to: 2, mouseX: nil)
        #expect(output.started.count == 3)
        scene.close()
        let stops = output.stops
        audio.request(1017)
        scene.close(); scene.setActive(true); scene.advance(to: 5000, mouseX: nil)
        #expect(output.stops == stops && output.started.last == 1017)
    }

    @MainActor @Test func cdRaftDrowningWaitsForFirstLossRedraw() {
        var deaths = 0
        for seed in 1...6 {
            let output = Output()
            var idle: [() -> Void] = []
            let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
            let scene = OriginalRaftScene(session: Self.raftSession(), random: OriginalRandomStream(seed: UInt32(seed)),
                                          audio: audio, clock: { 0 }) { _ in }
            scene.setActive(true)
            var tick = 0
            while scene.session.collision == nil && tick < 1500 {
                scene.advance(to: tick, mouseX: nil); tick += 3
            }
            #expect(scene.session.collision != nil)
            #expect(scene.session.pauseSteps == 100)
            #expect(output.started.last == 9006 && !output.started.contains(9001) && !output.started.contains(4001))
            let drowned = !(scene.session.collision?.drownedMembers.isEmpty ?? true)
            if drowned { deaths += 1 }
            scene.advance(to: tick - 2, mouseX: nil) // Nondue idle still performs first loss redraw.
            #expect(scene.session.pauseSteps == 99)
            output.callbacks.last?()
            while !idle.isEmpty { idle.removeFirst()() }
            #expect(output.started.last == (drowned ? 4001 : 9006))
            if drowned {
                output.callbacks.last?()
                while !idle.isEmpty { idle.removeFirst()() }
                let count = output.started.count
                scene.advance(to: tick - 1, mouseX: nil)
                #expect(output.started.count == count) // Ordinary frames do not repeat narration.
                scene.redraw()
                #expect(output.started.count == count + 1 && output.started.last == 4001)
            }
            scene.close()
        }
        #expect(deaths > 0)
    }

    @MainActor @Test func cdRaftCompletionClearsBeforeCallbackAndCancellationDiscardsIt() {
        for cancel in [false, true] {
            let output = Output()
            let audio = GameAudio(playback: output, scheduleIdle: { _ in })
            var callbacks: [() -> Void] = []
            var completions = 0
            let scene = OriginalRaftScene(session: Self.raftSession(living: [false]), random: OriginalRandomStream(seed: 1),
                audio: audio, clock: { 0 }, scheduleCompletion: { callbacks.append($0) }) { _ in
                    #expect(!audio.isPlaying)
                    completions += 1
                    audio.request(1017)
                }
            scene.setActive(true); scene.advance(to: 0, mouseX: nil)
            #expect(completions == 0 && !audio.isPlaying && callbacks.count == 1)
            if cancel { scene.close(); audio.request(1000) }
            callbacks.removeFirst()()
            #expect(completions == (cancel ? 0 : 1))
            let stops = output.stops
            scene.close()
            #expect(output.stops == stops && output.started.last == (cancel ? 1000 : 1017))
        }
    }

    @MainActor @Test func classicRaftRetainsCollisionAudioWithoutCDAmbience() {
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let scene = OriginalRaftScene(session: Self.raftSession(edition: .macintosh11),
            random: OriginalRandomStream(seed: 1), audio: audio, clock: { 0 }) { _ in }
        scene.setActive(true)
        var tick = 0
        while scene.session.collision == nil && tick < 1500 {
            scene.advance(to: tick, mouseX: nil); tick += 3
        }
        #expect(scene.session.collision != nil && output.started == [9006])
        let drowned = !(scene.session.collision?.drownedMembers.isEmpty ?? true)
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == (drowned ? [9006,9001] : [9006]))
        let stops = output.stops
        scene.close()
        #expect(output.stops == stops)
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func raftViewReappearanceResumesExistingSession(edition: GameEdition) {
        var tick = 0
        let audio = GameAudio(playback: Output(), scheduleIdle: { _ in })
        let scene = OriginalRaftScene(session: Self.raftSession(edition: edition), random: OriginalRandomStream(seed: 1),
            audio: audio, clock: { tick }) { _ in }
        scene.setActive(true); scene.advance(to: 0, mouseX: nil)
        let remaining = scene.session.remaining
        tick = 1; scene.viewDidDisappear()
        scene.advance(to: 9, mouseX: nil)
        #expect(scene.session.remaining == remaining)
        tick = 10; scene.setActive(true)
        scene.advance(to: 11, mouseX: nil)
        #expect(scene.session.remaining == remaining)
        scene.advance(to: 12, mouseX: nil)
        #expect(scene.session.remaining == remaining - 2)
        scene.close()
    }

    @MainActor @Test func hiddenRaftViewRetainsPendingCompletionUntilReappearance() {
        var callbacks: [() -> Void] = []
        var count = 0
        let scene = OriginalRaftScene(session: Self.raftSession(living: [false]), random: OriginalRandomStream(seed: 1),
            audio: GameAudio(playback: Output(), scheduleIdle: { _ in }), clock: { 0 },
            scheduleCompletion: { callbacks.append($0) }) { _ in count += 1 }
        scene.setActive(true); scene.advance(to: 0, mouseX: nil)
        scene.viewDidDisappear()
        callbacks.removeFirst()()
        #expect(count == 0)
        scene.setActive(true); scene.advance(to: 1, mouseX: nil)
        #expect(count == 1)
        scene.advance(to: 2, mouseX: nil)
        #expect(count == 1)
    }

    @MainActor @Test(arguments: [0, 1, 2])
    func raftOwnerTeardownCancelsSceneAndOldCompletion(exit: Int) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = GameAudio(playback: Output(), scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .rafting
        game.trip = trip
        var callbacks: [() -> Void] = [], count = 0
        let scene = OriginalRaftScene(session: Self.raftSession(living: [false]), random: game.random,
            audio: audio, clock: { 0 }, scheduleCompletion: { callbacks.append($0) }) { _ in count += 1 }
        game.registerRaftScene(scene)
        scene.setActive(true); scene.advance(to: 0, mouseX: nil)
        if exit == 0 { game.trip = nil }
        else if exit == 1 { game.trip = Journey(seed: 2, edition: .macintoshCD12) }
        else { trip.phase = .finished; game.trip = trip }
        audio.request(1017)
        callbacks.removeFirst()()
        scene.setActive(true); scene.advance(to: 10, mouseX: nil); scene.close()
        #expect(count == 0 && audio.isPlaying)
    }

    private static func raftSession(living: [Bool] = [true,true,true,true,true], edition: GameEdition = .macintoshCD12) -> OriginalRaftSession {
        var draws = [0,4]
        return OriginalRaftSession(input: .init(inventory: Array(repeating: 0, count: Inventory.itemCount(for: edition)),
            living: living, names: living.indices.map { "P\($0)" }, rain: 400), startTick: 0, edition: edition) { _ in draws.removeFirst() }
    }

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
