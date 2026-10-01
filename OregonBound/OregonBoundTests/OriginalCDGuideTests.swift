import Testing
@testable import OregonBound

struct OriginalCDGuideTests {
    @Test func everyLandmarkUsesItsEditionPageIncludingOregonBeforeLastPage() {
        let locations = ["independence", "kansas", "big-blue", "kearney", "chimney", "laramie", "rock",
                         "south-pass", "bridger", "green", "soda", "hall", "snake", "boise",
                         "blue-mountains", "walla", "dalles", "oregon"]
        let classic = [33,37,7,26,13,27,34,54,24,32,53,25,52,23,30,28,17,61]
        let cd = [35,40,8,28,14,29,36,64,26,34,63,27,62,25,32,30,18,72]
        for (index, location) in locations.enumerated() {
            #expect(OriginalGuide(locationID: location, edition: .macintosh11).page == classic[index])
            #expect(OriginalGuide(locationID: location, edition: .macintoshCD12).page == cd[index])
        }
        #expect(OriginalGuide(locationID: "unknown", edition: .macintoshCD12).page == 1)
    }

    @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func allPagesKeepOriginalAddressesAndIndexBounds(edition: GameEdition) {
        var guide = OriginalGuide(locationID: "unknown", edition: edition)
        let count = edition == .macintosh11 ? 61 : 73
        #expect(guide.pageCount == count)
        #expect(guide.pageLabel == " 1 of \(count)")
        for page in 1...count {
            #expect(guide.page == page)
            #expect(guide.textResource == 3151 + (page - 1) / 3)
            #expect(guide.textResourceEntry == 1 + (page - 1) % 3)
            guide.turn(forward: true)
        }
        #expect(guide.page == count)
        #expect(guide.pageLabel == "\(count) of \(count)")
        guide.openIndex()
        #expect(guide.initialIndexRow == count - 11)
        guide.select(count + 100)
        #expect(guide.selection == count)
        guide.select(-1)
        #expect(guide.selection == 1)
        guide.closeIndex(accept: false)
        #expect(guide.page == count)
        guide.openIndex(); guide.select(1); guide.closeIndex(accept: true)
        #expect(guide.page == 1)
        guide.turn(forward: false)
        #expect(guide.page == 1)
    }

    @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func loaderAddressesSlotsWithoutShiftingAfterMissingGroup(edition: GameEdition) {
        let count = edition == .macintosh11 ? 61 : 73
        let titles = (1...count + 2).map { "Topic \($0)" }
        var groups: [Int: [String]] = [:]
        for page in 1...count { groups[3151 + (page - 1) / 3, default: []].append("Body \(page)") }
        let all = OriginalResources.loadGuide(edition: edition, titles: titles, group: { groups[$0] })
        #expect(all.count == count)
        for (index, entry) in all.enumerated() {
            #expect(entry.id == index && entry.title == "Topic \(index + 1)" && entry.text == "Body \(index + 1)")
        }
        groups[3152] = nil
        groups[3153] = ["Body 7"]
        let partial = OriginalResources.loadGuide(edition: edition, titles: titles, group: { groups[$0] })
        #expect(partial.count == count - 5)
        #expect(partial.first { $0.id == 9 }?.text == "Body 10")
        #expect(partial.last?.id == count - 1)
        #expect(OriginalResources.loadGuide(edition: edition, titles: [], group: { groups[$0] }).isEmpty)
    }

    @Test func narrationToggleCompletionAndNavigationMatchSharedChannel() {
        var guide = OriginalGuide(locationID: "oregon", edition: .macintoshCD12)
        #expect(guide.toggleNarration(isAudioPlaying: true) == .request(6072))
        #expect(guide.toggleNarration(isAudioPlaying: true) == .stop)
        #expect(guide.toggleNarration(isAudioPlaying: false) == .request(6072))
        #expect(guide.toggleNarration(isAudioPlaying: false) == .request(6072))
        #expect(guide.turn(forward: true) == .stop)
        #expect(guide.toggleNarration(isAudioPlaying: false) == .request(6073))
        #expect(guide.turn(forward: true) == .none)
        #expect(guide.toggleNarration(isAudioPlaying: true) == .stop)
        #expect(guide.openIndex() == .stop)
        #expect(guide.close() == .stop)
        #expect(guide.toggleNarration(isAudioPlaying: true) == .request(6073))
    }

    @Test func classicGuideNeverTouchesSharedAudio() {
        var guide = OriginalGuide(locationID: "independence")
        #expect(!guide.hasNarration)
        #expect(guide.toggleNarration(isAudioPlaying: true) == .none)
        #expect(guide.turn(forward: true) == .none)
        #expect(guide.openIndex() == .none)
        #expect(guide.close() == .none)
    }

    @Test func completionBeforeIdleAllowsReplayAndIndexClearsQueuedAudio() {
        let output = OriginalAudioBackendTests.Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        var guide = OriginalGuide(locationID: "unknown", edition: .macintoshCD12)
        #expect(!audio.isPlaying)
        audio.perform(guide.toggleNarration(isAudioPlaying: audio.isPlaying))
        #expect(audio.isPlaying && output.started == [6001])
        output.callbacks.last?()
        #expect(!audio.isPlaying)
        audio.perform(guide.toggleNarration(isAudioPlaying: audio.isPlaying))
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(audio.isPlaying && output.started == [6001, 6001])
        audio.enqueue(9003)
        audio.perform(guide.openIndex())
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(!audio.isPlaying && output.started == [6001, 6001])
        audio.enabled = false
        audio.perform(guide.toggleNarration(isAudioPlaying: audio.isPlaying))
        #expect(!audio.isPlaying)
        audio.enabled = true
        audio.perform(guide.toggleNarration(isAudioPlaying: audio.isPlaying))
        #expect(output.started == [6001, 6001, 6001])
        audio.perform(guide.close())
        #expect(!audio.isPlaying)
    }
}
