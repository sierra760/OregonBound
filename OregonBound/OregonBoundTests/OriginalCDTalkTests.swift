import Foundation
import Testing
@testable import OregonBound

struct OriginalCDTalkTests {
    @Test func allConversationPairsHaveDistinctCDSoundIDs() {
        var ids = Set<Int>()
        for table in 3100...3117 {
            for quote in 1...3 {
                let selection = OriginalTalkRules.Selection(resourceID: table, quoteIndex: quote, edition: .macintoshCD12)
                let sound = 3100 + (table - 3100) * 10 + quote
                #expect(selection.soundResourceID == sound)
                ids.insert(sound)
                #expect(OriginalTalkRules.Selection(resourceID: table, quoteIndex: quote).soundResourceID == nil)
            }
        }
        #expect(ids.count == 54 && ids.contains(3101) && ids.contains(3273))
        #expect(OriginalTalkRules.Selection(resourceID: Int.max, quoteIndex: 1, edition: .macintoshCD12).soundResourceID == nil)
    }

    @Test func everyCDLetterSelectsItsOwnPortraitAndSharedBackground() throws {
        for byte in UInt8(ascii: "A")...UInt8(ascii: "W") {
            let letter = String(UnicodeScalar(byte))
            let selection = OriginalTalkRules.Selection(resourceID: 3100, quoteIndex: 1, edition: .macintoshCD12)
            let content = try #require(OriginalTalkRules.content(selection: selection, strings: [letter, "Synthetic quote"]))
            #expect(content.portrait == Int(byte) - 64)
            #expect(content.portraitResourceID == 16180 + Int(byte) - 64 && content.portraitFrame == 0)
            #expect(content.backgroundResourceID == 16180 && content.backgroundFrame == 0)
            #expect(content.text == "Synthetic quote")
        }
        for bad in ["", "@", "X", "1", "é"] {
            #expect(OriginalTalkRules.content(selection: .init(resourceID: 3100, quoteIndex: 1, edition: .macintoshCD12), strings: [bad, "Synthetic"]) == nil)
        }
        let classic = try #require(OriginalTalkRules.content(selection: .init(resourceID: 3100, quoteIndex: 1), strings: ["6", "Classic"]))
        #expect(classic.portraitResourceID == 16080 && classic.portraitFrame == 6)
        #expect(classic.backgroundResourceID == 16080 && classic.backgroundFrame == 9)
        #expect(OriginalTalkRules.content(selection: .init(resourceID: 3100, quoteIndex: 1), strings: ["A", "CD"]) == nil)
    }

    @Test func CDJourneyCapturesEditionAndUsesDestinationWithoutMutatingTrip() throws {
        var state = OriginalTalkRules.State()
        var trip = Journey(seed: 199, edition: .macintoshCD12)
        trip.phase = .travel; trip.locationID = "south-pass"; trip.destinationID = "green"
        let snapshot = trip
        for (quote, sound) in [(2,3192),(3,3193),(1,3191)] {
            let selection = try #require(OriginalTalkRules.open(trip: trip, state: &state))
            #expect(selection.edition == .macintoshCD12 && selection.quoteIndex == quote && selection.soundResourceID == sound)
        }
        #expect(trip == snapshot)
    }

    @MainActor @Test func controllerOrdersPaneCloseBeforeConversationStart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = OriginalAudioBackendTests.Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let store = JourneyStore(directory: root, edition: .macintoshCD12, defaultPreferences: .init())
        let game = GameController(store: store, audio: audio)
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .landmark
        game.trip = trip
        game.panel = .guide
        audio.request(6035)
        game.open(.talk)
        #expect(output.started == [6035, 3102] && output.stops == 1)
        #expect(audio.isPlaying)
        game.open(.talk)
        #expect(output.started == [6035, 3102, 3103] && output.stops == 2)
        game.open(.guide)
        #expect(!audio.isPlaying && output.stops == 3)
        game.open(.talk)
        #expect(output.started.last == 3101 && audio.isPlaying)
        game.panel = nil
        #expect(!audio.isPlaying)
        audio.enabled = false
        game.open(.talk)
        #expect(!audio.isPlaying && output.started.count == 4)
        game.panel = nil
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(!audio.isPlaying)
    }

    @MainActor @Test(arguments: [GamePanel.talk, .guide])
    func finalPartyDeathClosesNarrationBeforeQueueingDeathSound(panel: GamePanel) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = OriginalAudioBackendTests.Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
                                                       defaultPreferences: .init()), audio: audio)
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        trip.phase = .travel; trip.destinationID = "kansas"; game.trip = trip
        game.open(panel)
        if panel == .guide { audio.request(6035) }
        #expect(audio.isPlaying)
        game.perform {
            for index in $0.members.indices { $0.members[index].health = 0 }
            $0.phase = .finished
            $0.won = false
        }
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(game.panel == nil && game.trip?.phase == .finished)
        #expect(output.stops == 1)
        #expect(output.started.last == OriginalDeathPresentationRules.soundResource)
        #expect(audio.isPlaying)
    }

    @MainActor @Test func classicTalkLeavesExistingAudioAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = OriginalAudioBackendTests.Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintosh11), audio: audio)
        var trip = Journey(seed: 1); trip.phase = .landmark; game.trip = trip
        audio.request(9002)
        game.open(.talk); game.open(.talk); game.panel = nil
        #expect(output.started == [9002] && output.stops == 0 && audio.isPlaying)
    }
}
