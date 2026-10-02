import Testing
import Foundation
#if os(macOS)
import AppKit
import SwiftUI
#endif
@testable import OregonBound

struct OriginalAudioBackendTests {
    #if os(macOS)
    @MainActor @Test func mountedTabletHelpReenablesWhenApplicationBecomesActive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()))
        game.creatingGame = true // Only Help is visible during setup.
        game.applicationActive = false
        _ = NSApplication.shared
        let content = OriginalTabletHelpBar(game: game).frame(width: 400, height: 72)
            .background(Color.white).environment(\.colorScheme, .light)
            .transaction { $0.animation = nil }
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 72),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func pixels() throws -> Data {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let inactive = try pixels()
        // Keep the same mounted view and change no other controller property.
        game.applicationActive = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(try pixels() != inactive, "Help must leave its disabled appearance after activation")
        game.applicationActive = false
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(try pixels() == inactive)
    }
    #endif

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func helpAboutEntryRejectsInactiveAndCoveredRequestsWithoutChangingItsAudioMode(edition: GameEdition) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        var tick: UInt32 = 100
        let game = GameController(store: JourneyStore(directory: root, edition: edition, defaultPreferences: .init()),
            random: OriginalRandomStream(seed: 17), audio: audio, clock: { tick })
        game.applicationActive = false
        game.presentAbout(); game.presentAbout(alternate: true)
        #expect(!game.showingAbout && output.started.isEmpty)
        game.applicationActive = true
        if edition == .macintoshCD12 {
            game.presentUserGuide(); game.presentAbout(alternate: true)
            #expect(!game.showingAbout && game.userGuideOpening != nil && output.started.isEmpty)
            game.userGuideCloseAction()()
        }
        game.presentAbout(alternate: true)
        let old = game.aboutAction()
        game.presentAbout(alternate: false)
        tick = 103; old(.poll(showsSystemInformation: false))
        // Drain the initial theme, revealing the alternate request already queued.
        output.callbacks.first?()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == (edition == .macintoshCD12 ? [2000, 10000] : []))
        old(.close)
        game.presentAbout()
        old(.close)
        #expect(game.showingAbout && game.random.seed == 17 && game.trip == nil)
        game.aboutAction()(.close)
    }

    @MainActor @Test func standaloneGuidePausesGameAndAudioAndRetiresStaleCloseCallbacks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), random: OriginalRandomStream(seed: 71), audio: audio)
        var trip = Journey(seed: 71, edition: .macintoshCD12); trip.phase = .travel
        game.trip = trip
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(game.trip)
        audio.request(2000)
        game.presentUserGuide()
        let first = try #require(game.userGuideOpening)
        let closeFirst = game.userGuideCloseAction()
        #expect(game.isOriginalModalPresented && !game.canUseGameMenus && !audio.isPlaying)
        game.presentUserGuide(); #expect(game.userGuideOpening?.id == first.id)
        for _ in 0..<50 { game.tick(); game.pollLandmarkAudio(); game.pollNotification() }
        #expect(try encoder.encode(game.trip) == before)
        #expect(game.random.seed == 71 && output.started == [2000])
        closeFirst(); #expect(game.userGuideOpening == nil)
        game.presentUserGuide(); let second = try #require(game.userGuideOpening)
        closeFirst(); #expect(game.userGuideOpening?.id == second.id)
        game.userGuideCloseAction()()
        game.applicationActive = false; game.presentUserGuide()
        #expect(game.userGuideOpening == nil)
        game.applicationActive = true; game.showingAbout = true; game.presentUserGuide()
        #expect(game.userGuideOpening == nil)
        let classic = GameController(store: JourneyStore(directory: root.appendingPathComponent("classic"),
            edition: .macintosh11, defaultPreferences: .init()), audio: audio)
        classic.presentUserGuide(); #expect(classic.userGuideOpening == nil)
    }

    @MainActor @Test func arrivalAndMapReplaceAnIllustratedNoticeBeforeLandmarkNarration() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        var tick: UInt32 = 0
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .travel
        trip.destinationID = "kansas"; trip.legDistance = 102
        game.trip = trip
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        let notice = game.notificationAction()
        game.perform { $0.phase = .river; $0.locationID = "kansas" }
        #expect(game.cdNotification == nil && game.landmarkPaneVisible)
        for now in UInt32(1)...64 { tick = now; game.pollLandmarkAudio() }
        notice(.dismiss)
        #expect(output.started == [4001,1001] && audio.isPlaying)
        game.showingTravelMap = true
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        #expect(game.cdNotification != nil)
        game.open(.map)
        #expect(game.cdNotification == nil && !audio.isPlaying)
    }

    @MainActor @Test func cdNoticeConsumesOnlyNewEventsAndOwnsItsOpening() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        var tick: UInt32 = 0
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), random: OriginalRandomStream(seed: 17), audio: audio, clock: { tick })
        var trip = Journey(seed: 17, edition: .macintoshCD12); trip.phase = .travel
        OriginalTrailEvents.record(65, in: &trip)
        game.trip = trip
        game.perform { $0.record("A new journal entry without an illustrated event.") }
        #expect(game.cdNotification == nil && output.started.isEmpty)
        game.perform { OriginalTrailEvents.record(29, in: &$0); OriginalTrailEvents.record(65, in: &$0) }
        #expect(game.cdNotification?.art == 2 && output.started == [4007])
        #expect(game.random.seed == 17)
        let old = game.notificationAction()
        old(.redraw)
        #expect(output.started == [4007])
        tick = 20
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        #expect(game.cdNotification?.art == 1 && output.started == [4007,4001])
        old(.dismiss); old(.guide)
        #expect(game.cdNotification?.art == 1 && game.panel == nil && audio.isPlaying)
        let fire = game.notificationAction()
        fire(.dismiss)
        #expect(game.cdNotification == nil && !audio.isPlaying)
        game.perform { OriginalTrailEvents.record(29, in: &$0) }
        game.notificationAction()(.guide)
        #expect(game.panel == .guide && game.guidePage == 61 && game.cdNotification == nil)
        #expect(!audio.isPlaying && game.random.seed == 17)
    }

    @MainActor @Test func cdNoticeExpiresWhileCoveredButDoesNotDispatchDuringModal() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 3, edition: .macintoshCD12); trip.phase = .travel
        game.trip = trip
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        game.trip?.phase = .hunting
        #expect(game.cdNotification != nil && !game.notificationPaneVisible)
        game.showingIntroduction = true
        for now in UInt32(1)...600 { tick = now; game.pollNotification() }
        #expect(game.cdNotification != nil && audio.isPlaying)
        game.showingIntroduction = false
        for now in UInt32(601)...604 { tick = now; game.pollNotification() }
        #expect(game.cdNotification == nil && !audio.isPlaying)
    }

    @MainActor @Test func cdNoticeReplacementClosesBeforeIncomingEndingAudio() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        var trip = Journey(seed: 3, edition: .macintoshCD12); trip.phase = .travel
        game.trip = trip
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        let old = game.notificationAction()
        game.perform { $0.phase = .finished; $0.won = false }
        old(.dismiss)
        #expect(game.cdNotification == nil && output.started == [4001,9001] && audio.isPlaying)
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func illustratedEventsRespectTheCurrentPaneAndEdition(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: GameAudio(playback: output, scheduleIdle: { _ in }))
        var trip = Journey(seed: 1, edition: edition); trip.phase = .landmark
        game.trip = trip
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        #expect(game.cdNotification == nil)
        game.trip?.phase = .travel
        game.panel = .guide
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        #expect(game.cdNotification == nil)
        game.panel = nil
        game.perform { $0.record("An uneventful pulse.") }
        #expect(game.cdNotification == nil)
        game.perform { OriginalTrailEvents.record(65, in: &$0) }
        #expect((game.cdNotification != nil) == (edition == .macintoshCD12))
        game.panel = .supplies
        #expect(game.cdNotification == nil && !game.audio.isPlaying)
    }

    @MainActor @Test(arguments: [false, true], [false, true])
    func cdLossReactivationWaitsForBothInputsOnce(nativeFirst: Bool, modal: Bool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        trip.phase = .finished; trip.won = false
        game.trip = trip
        let loss = game.endingAction()
        game.applicationActive = false
        game.gameWindowActivationChanged(false)
        game.showingIntroduction = modal
        if nativeFirst {
            game.gameWindowActivationChanged(true)
            #expect(output.started == [9001] && !audio.isPlaying)
            game.applicationActive = true
        } else {
            game.applicationActive = true
            #expect(output.started == [9001] && !audio.isPlaying)
            game.gameWindowActivationChanged(true)
        }
        #expect(output.started == (modal ? [9001] : [9001,9001]))
        if modal {
            game.showingIntroduction = false
            loss(.redraw) // Native pane's onChange callback after modal reveal.
        }
        #expect(output.started == [9001,9001] && audio.isPlaying)
        game.gameWindowActivationChanged(true)
        game.applicationActive = true
        #expect(output.started == [9001,9001] && audio.isPlaying)
    }

    @MainActor @Test(arguments: [0,1,2]) func cdLoadedEndingInitializesOnlyItsDisplayedPane(stage: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("ending.json")
        var trip = Journey(seed: 4, edition: .macintoshCD12)
        trip.phase = .finished; trip.won = stage != 0
        trip.originalEndingStage = stage == 2 ? .score : .arrival
        try JSONEncoder().encode(SavedJourney(format: "OregonBound", version: 2,
            journey: trip, edition: .macintoshCD12)).write(to: source)
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        game.showAttract(); game.resume(from: source)
        #expect(game.error == nil && game.trip?.id == trip.id)
        #expect(output.started == (stage == 2 ? [9007] : [9007, stage == 0 ? 9001 : 1017]))
        #expect(audio.isPlaying == (stage != 2))
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func endingArrivalContinuesIntoScoreThenStopsBeforeLegends(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: audio)
        game.showAttract()
        var trip = Journey(seed: 7, edition: edition)
        trip.phase = .finished; trip.won = true
        game.trip = trip
        #expect(output.started.last == (edition == .macintoshCD12 ? 1017 : 9007))
        let arrival = game.endingAction()
        let before = output.started
        arrival(.redraw)
        #expect(output.started == before)
        arrival(.continueArrival)
        #expect(game.trip?.originalEndingStage == .score)
        #expect(output.started == before && audio.isPlaying)
        let score = game.endingAction()
        arrival(.exitLoss); arrival(.continueArrival)
        #expect(game.trip?.originalEndingStage == .score)
        score(.submitScore(name: "Traveler"))
        game.showAttract()
        #expect(game.trip == nil && audio.isPlaying)
        #expect(output.started == (edition == .macintoshCD12 ? before + [2000] : before))
        if edition == .macintoshCD12 { #expect(game.cdAttractPage == .legends) }
    }

    @MainActor @Test(arguments: [false, true])
    func cdLossRedrawAndExitOwnAudio(muted: Bool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        game.sound = !muted; game.showAttract()
        var trip = Journey(seed: 3, edition: .macintoshCD12)
        trip.phase = .finished; trip.won = false
        game.trip = trip
        #expect(output.started == (muted ? [] : [9007,9001]))
        let loss = game.endingAction()
        game.trip = trip // State publication is not a logical redraw.
        #expect(output.started == (muted ? [] : [9007,9001]))
        loss(.redraw)
        #expect(output.started == (muted ? [] : [9007,9001,9001]))
        game.showingIntroduction = true; loss(.redraw); loss(.exitLoss)
        #expect(game.trip != nil && output.started.count == (muted ? 0 : 3))
        game.showingIntroduction = false
        game.applicationActive = false; loss(.redraw); loss(.exitLoss)
        #expect(game.trip != nil && output.started.count == (muted ? 0 : 3))
        game.applicationActive = true
        loss(.exitLoss)
        #expect(game.trip == nil && !audio.isPlaying)
        game.showAttract()
        #expect(output.started.last == (muted ? nil : 2000))
        loss(.redraw); loss(.exitLoss)
        #expect(game.cdAttractPage == .legends && audio.isPlaying == !muted)
    }

    @MainActor @Test(arguments: [false, true])
    func cdEndingOldCallbacksCannotAffectReplacementJourney(won: Bool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        trip.phase = .finished; trip.won = won
        game.trip = trip
        let retired = game.endingAction()
        var replacement = Journey(seed: 2, edition: .macintoshCD12)
        replacement.phase = .finished; replacement.won = won
        game.trip = replacement
        let expected = output.started
        retired(.redraw); retired(.continueArrival); retired(.exitLoss); retired(.submitScore(name: "Old"))
        #expect(game.trip?.id == replacement.id && output.started == expected && audio.isPlaying)
        game.completeDeparture(.exitGame)
        game.beginRegistration()
        retired(.redraw); retired(.exitLoss)
        #expect(game.creatingGame && output.started.last == 10001 && audio.isPlaying)
    }

    @MainActor @Test(arguments: [0,1,2]) func cdReturnFromSetupJourneyOrEndingShowsLegends(kind: Int) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        game.showAttract()
        #expect(game.cdAttractPage == .title)
        if kind == 0 { game.beginRegistration(); game.completeDeparture(.exitGame) }
        else {
            var trip = Journey(seed: 7, edition: .macintoshCD12)
            trip.phase = kind == 1 ? .landmark : .finished
            game.trip = trip
            if kind == 1 { game.completeDeparture(.exitGame) } else { game.mainMenu() }
        }
        game.showAttract()
        #expect(game.cdAttractPage == .legends)
        #expect(output.started.filter { $0 == 9007 }.count == 1)
    }

    @MainActor @Test func cdCancelledTitleLoadOpensLegendsButExistingLegendsKeepsTimer() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.sound = false; game.showAttract()
        let title = game.attractAction()
        game.cancelLoadGameSelection()
        #expect(game.cdAttractPage == .legends && game.error == nil)
        title(.advance); title(.travel)
        #expect(game.cdAttractPage == .legends && !game.creatingGame)
        let legends = game.attractAction()
        for now in UInt32(1)...100 { tick = now; legends(.poll) }
        game.cancelLoadGameSelection()
        for now in UInt32(101)...3599 { tick = now; legends(.poll) }
        #expect(game.cdAttractPage == .legends)
        tick = 3600; legends(.poll)
        #expect(game.cdAttractPage == .title)
    }

    @MainActor @Test func cdFailedLoadReturnsToLegendsAfterErrorAcknowledgment() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        game.showAttract()
        let title = game.attractAction()
        game.resume(from: root.appendingPathComponent("missing.json"))
        #expect(game.error != nil && game.cdAttractPage == .title)
        game.error = nil
        #expect(game.cdAttractPage == .legends && output.started == [9007,2000])
        title(.advance)
        #expect(game.cdAttractPage == .legends && audio.isPlaying)
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func fileImporterCancellationIsNotAnErrorAndLiveJourneyCannotBeRetired(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: GameAudio(playback: Output(), scheduleIdle: { _ in }))
        game.showAttract()
        game.handleLoadGameFailure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        #expect(game.error == nil)
        #expect(game.cdAttractPage == (edition == .macintoshCD12 ? .legends : .title))
        let trip = Journey(seed: 2, edition: edition)
        game.trip = trip
        game.cancelLoadGameSelection()
        #expect(game.trip?.id == trip.id)
    }

    @MainActor @Test func cdAttractWaitsForStartupAndBusyThemeAtEachTimerBoundary() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0, idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), random: OriginalRandomStream(seed: 7), audio: audio, clock: { tick })
        game.showAttract()
        game.showAttract()
        let titleAction = game.attractAction()
        #expect(output.started == [9007] && game.cdAttractPage == .title)
        for now in UInt32(1)...300 { tick = now; titleAction(.poll) }
        #expect(game.cdAttractPage == .title && output.started == [9007])
        output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() }
        for now in UInt32(301)...599 { tick = now; titleAction(.poll) }
        #expect(game.cdAttractPage == .title)
        tick = 600; titleAction(.poll)
        #expect(game.cdAttractPage == .legends && output.started == [9007,2000])
        titleAction(.advance); titleAction(.travel)
        #expect(game.cdAttractPage == .legends && !game.creatingGame)
        let legendsAction = game.attractAction()
        for now in UInt32(601)...900 { tick = now; legendsAction(.poll) }
        #expect(game.cdAttractPage == .legends)
        legendsAction(.advance)
        #expect(game.cdAttractPage == .title && output.started == [9007,2000,2000])
        game.attractAction()(.travel)
        #expect(game.creatingGame && game.setupDialog == .welcome)
        #expect(output.started == [9007,2000,2000,10001] && audio.isPlaying)
        legendsAction(.advance); titleAction(.poll)
        #expect(output.started.last == 10001 && audio.isPlaying && game.random.seed == 7)
        game.completeDeparture(.exitGame)
        game.showAttract()
        #expect(output.started == [9007,2000,2000,10001,2000]) // Startup is session-scoped.
    }

    @MainActor @Test func cdAttractMuteAndModalCoveragePreserveCapturedTimer() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.sound = false; game.showAttract()
        let action = game.attractAction()
        for now in UInt32(1)...599 { tick = now; action(.poll) }
        game.showingIntroduction = true
        for now in UInt32(600)...900 { tick = now; action(.poll) }
        #expect(game.cdAttractPage == .title && output.started.isEmpty)
        game.showingIntroduction = false
        game.applicationActive = false
        for now in UInt32(901)...1000 { tick = now; action(.poll) }
        game.applicationActive = true; game.sound = true
        tick = 1001; action(.poll)
        #expect(game.cdAttractPage == .legends && output.started == [2000])
        let legends = game.attractAction()
        game.presentAbout()
        for now in UInt32(1002)...1500 { tick = now; legends(.poll) }
        #expect(game.cdAttractPage == .legends)
        game.aboutAction()(.close)
        for now in UInt32(1501)...1799 { tick = now; legends(.poll) }
        #expect(game.cdAttractPage == .legends)
        tick = 1800; legends(.poll)
        #expect(game.cdAttractPage == .title && output.started == [2000,2000,2000])
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func attractLoadButtonsAndOwnerRetirementFollowTheirPage(edition: GameEdition) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let store = JourneyStore(directory: root, edition: edition, defaultPreferences: .init())
        var tick: UInt32 = 0
        let game = GameController(store: store, audio: audio, clock: { tick })
        game.showAttract()
        #expect(game.prepareLoadGame(fromAttractButton: true))
        #expect(audio.isPlaying && output.started == [9007])
        game.attractAction()(.advance)
        if edition == .macintoshCD12 {
            #expect(game.prepareLoadGame(fromAttractButton: false))
            #expect(audio.isPlaying)
            #expect(game.prepareLoadGame(fromAttractButton: true))
            #expect(!audio.isPlaying && game.cdAttractPage == .legends)
            // Cancelled chooser does not recreate or reset the underlying page.
            game.fileChooserPresented = true
            tick = 500; game.attractAction()(.poll)
            game.fileChooserPresented = false
            for now in UInt32(501)...800 { tick = now; game.attractAction()(.poll) }
            #expect(game.cdAttractPage == .title && output.started == [9007,2000,2000])
        }
        let stale = game.attractAction()
        var trip = Journey(seed: 3, edition: edition); trip.phase = .landmark; trip.locationID = "kearney"
        try store.save(trip)
        game.resume()
        #expect(game.trip?.id == trip.id && game.error == nil)
        if edition == .macintoshCD12 { #expect(!audio.isPlaying) }
        for now in UInt32(801)...864 { tick = now; game.pollLandmarkAudio() }
        stale(.advance); stale(.travel)
        if edition == .macintoshCD12 { #expect(output.started.last == 1003 && audio.isPlaying) }
        #expect(game.trip?.id == trip.id && !game.creatingGame)
    }

    @MainActor @Test func realWindowDeactivationClearsCDAttractOnceAndStopsItsDispatch() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.showAttract()
        game.gameWindowActivationChanged(false)
        #expect(!audio.isPlaying)
        let stops = output.stops
        for now in UInt32(1)...600 { tick = now; game.attractAction()(.poll) }
        #expect(game.cdAttractPage == .title && output.started == [9007])
        game.gameWindowActivationChanged(false)
        #expect(output.stops == stops)
        game.gameWindowActivationChanged(true)
        for now in UInt32(601)...900 { tick = now; game.attractAction()(.poll) }
        #expect(game.cdAttractPage == .legends && output.started == [9007,2000])
        let old = game.attractAction()
        var selectedData = false
        game.chooseGameData = { selectedData = true }
        game.requestGameData()
        old(.advance); old(.travel)
        #expect(selectedData && !audio.isPlaying && !game.creatingGame)
    }


    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func aboutOwnsOpeningAndRetiresOnlyItsOwnCallbacks(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 100
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        let seed = game.random.seed
        audio.request(9007)
        game.presentAbout(alternate: true)
        let oldAction = game.aboutAction()
        #expect(game.showingAbout)
        #expect(output.started == (edition == .macintoshCD12 ? [9007,2000] : [9007]))
        game.presentAbout(alternate: false)
        tick = 102; oldAction(.poll(showsSystemInformation: false))
        output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() }
        #expect(!audio.isPlaying)
        tick = 103; oldAction(.poll(showsSystemInformation: false))
        #expect(output.started == (edition == .macintoshCD12 ? [9007,2000,10000] : [9007]))
        oldAction(.close)
        if edition == .macintoshCD12 { #expect(!audio.isPlaying) }
        game.presentAbout()
        let currentAction = game.aboutAction()
        tick = 200; oldAction(.poll(showsSystemInformation: false)); oldAction(.close)
        #expect(game.showingAbout)
        #expect(output.started == (edition == .macintoshCD12 ? [9007,2000,10000,2000] : [9007]))
        currentAction(.close)
        #expect(!game.showingAbout && game.random.seed == seed)
    }

    @MainActor @Test func aboutCreditsRequestsRespectInformationActivityMuteAndBoundedQueue() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.presentAbout(alternate: true)
        let action = game.aboutAction()
        for now in UInt32(1)...60 { tick = now; action(.poll(showsSystemInformation: false)) }
        #expect(output.started == [2000])
        // Twenty requests fill the source's eight-entry FIFO; completion drains exactly eight.
        for _ in 0..<9 { output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() } }
        #expect(output.started == [2000] + Array(repeating: 10000, count: 8))
        #expect(!audio.isPlaying)
        tick = 100; action(.poll(showsSystemInformation: true))
        game.applicationActive = false
        tick = 120; action(.poll(showsSystemInformation: false))
        #expect(!audio.isPlaying)
        game.applicationActive = true
        action(.poll(showsSystemInformation: false))
        #expect(audio.isPlaying && output.started.count == 10)
        game.sound = false
        tick = 123; action(.poll(showsSystemInformation: false))
        game.sound = true
        tick = 125; action(.poll(showsSystemInformation: false))
        #expect(!audio.isPlaying)
        tick = 126; action(.poll(showsSystemInformation: false))
        #expect(audio.isPlaying && output.started.count == 11)
        tick = 129; action(.poll(showsSystemInformation: false))
        let lateCompletion = output.callbacks.last
        action(.close)
        audio.request(5000)
        lateCompletion?(); while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started.last == 5000 && audio.isPlaying)
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func landmarkNarrationFollowsLogicalPaneReplacement(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        var tick: UInt32 = 0
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: edition); trip.phase = .landmark; trip.locationID = "kearney"
        game.trip = trip
        let seed = game.random.seed
        for now in UInt32(1)...63 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started.isEmpty)
        tick = 64; game.pollLandmarkAudio()
        #expect(output.started == (edition == .macintoshCD12 ? [1003] : []))
        game.panel = .talk
        #expect(!audio.isPlaying && !game.landmarkPaneVisible)
        audio.request(5000) // Incoming pane recording must survive outgoing cleanup.
        game.pollLandmarkAudio()
        #expect(audio.isPlaying && output.started.last == 5000)
        game.panel = nil
        tick = 65; game.pollLandmarkAudio()
        #expect(game.landmarkPaneVisible)
        for now in UInt32(66)...128 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == (edition == .macintoshCD12 ? [1003,5000,1003] : [5000]))
        game.open(.map)
        #expect(!game.landmarkPaneVisible)
        if edition == .macintoshCD12 { #expect(!audio.isPlaying) }
        game.open(.map)
        for now in UInt32(129)...192 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == (edition == .macintoshCD12 ? [1003,5000,1003,1003] : [5000]))
        #expect(game.random.seed == seed)
        game.trip = nil
        if edition == .macintoshCD12 { #expect(!audio.isPlaying) }
    }

    @MainActor @Test func riverCoveragePreservesLandmarkDeadlineWhileForkReplacesIt() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .river; trip.locationID = "kansas"
        game.trip = trip
        game.showingRouteDecision = true
        for now in UInt32(1)...100 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started.isEmpty && !game.landmarkPaneVisible)
        game.showingRouteDecision = false
        for now in UInt32(101)...104 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [1001])
        trip.phase = .fork; trip.locationID = "south-pass"; game.trip = trip
        game.showingRouteDecision = true
        #expect(!audio.isPlaying)
        for now in UInt32(105)...200 { tick = now; game.pollLandmarkAudio() }
        game.showingRouteDecision = false
        for now in UInt32(201)...263 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [1001])
        tick = 264; game.pollLandmarkAudio()
        #expect(output.started == [1001,1007])
    }

    @MainActor @Test func landmarkWeatherRecreationWaitsForConditionsDrawAndPreservesAudio() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var idle: [() -> Void] = [], tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .landmark; trip.locationID = "kearney"
        trip.original?.weather.category = 0; trip.original?.weather.snow = 0
        game.trip = trip; game.showConditions()
        for now in UInt32(1)...64 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [1003] && game.cdLandmark.artwork?.colorResource == 15430)
        tick = 80; trip.original?.weather.category = 2; trip.original?.weather.snow = 1
        game.trip = trip; game.tick()
        #expect(game.cdLandmark.artwork?.colorResource == 15430)
        game.pollConditions()
        #expect(game.cdLandmark.artwork?.colorResource == 15433 && audio.isPlaying && output.stops == 0)
        output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() }
        for now in UInt32(81)...143 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [1003])
        tick = 144; game.pollLandmarkAudio()
        #expect(output.started == [1003,1003])
        tick = 160; trip.original?.weather.snow = 0; game.trip = trip; game.tick(); game.pollConditions()
        #expect(game.cdLandmark.artwork?.colorResource == 15433)
        output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() }
        for now in UInt32(161)...240 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [1003,1003])
    }

    @MainActor @Test func landmarkMuteConsumesCueAndBusyPlaybackUsesSharedQueue() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var idle: [() -> Void] = [], tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .landmark
        game.trip = trip; game.sound = false
        for now in UInt32(1)...64 { tick = now; game.pollLandmarkAudio() }
        game.sound = true
        for now in UInt32(65)...128 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started.isEmpty)
        game.open(.map); game.open(.map)
        audio.request(9007)
        for now in UInt32(129)...192 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [9007])
        output.callbacks.last?(); while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9007,1000])
        let stops = output.stops
        game.applicationActive = false; game.showingIntroduction = true
        for now in UInt32(193)...300 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started == [9007,1000] && output.stops == stops && audio.isPlaying)
        game.applicationActive = true; game.showingIntroduction = false
        var replacement = Journey(seed: 2, edition: .macintoshCD12); replacement.phase = .departure
        game.trip = replacement
        #expect(output.started == [9007,1000,10002] && audio.isPlaying)
        // The retired landmark must not clear the new setup recording.
        for now in UInt32(301)...400 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started.last == 10002 && audio.isPlaying)
        game.completeDeparture(.exitGame)
        #expect(!audio.isPlaying)
    }

    @MainActor @Test func coveredLandmarkKeepsArtworkUntilWeatherActuallyRedraws() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .river; trip.locationID = "kansas"
        trip.original?.weather.category = 0; trip.original?.weather.snow = 0
        game.trip = trip; game.showConditions(); game.showingRouteDecision = true
        tick = 20; trip.original?.weather.snow = 1; game.trip = trip
        game.tick(); game.pollConditions()
        #expect(game.cdLandmark.artwork?.colorResource == 15410)
        game.showingRouteDecision = false
        #expect(game.cdLandmark.artwork?.colorResource == 15410) // Reveal is not recreation.
        game.showingRouteDecision = true
        tick = 30; trip.original?.weather.category = 2; game.trip = trip
        game.tick(); game.pollConditions()
        #expect(game.cdLandmark.artwork?.colorResource == 15413)
        for now in UInt32(31)...100 { tick = now; game.pollLandmarkAudio() }
        #expect(output.started.isEmpty)
        game.showingRouteDecision = false
        tick = 101; game.pollLandmarkAudio(); tick = 102; game.pollLandmarkAudio()
        #expect(output.started == [1001])
        game.pendingDeparture = .exitGame
        #expect(!audio.isPlaying && !game.landmarkPaneVisible)
    }

    @MainActor @Test func landmarkClosePrecedesTerminalDeathRecording() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var idle: [() -> Void] = [], tick: UInt32 = 0
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        var trip = Journey(seed: 1, edition: .macintoshCD12); trip.phase = .landmark
        game.trip = trip
        for now in UInt32(1)...64 { tick = now; game.pollLandmarkAudio() }
        game.perform { value in
            for index in value.members.indices { value.members[index].health = 0 }
            value.phase = .finished; value.won = false
        }
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(game.trip?.phase == .finished)
        #expect(output.started == [1000,9001])
        #expect(audio.isPlaying)
    }

    @MainActor @Test func cdWelcomeRequestsNarrationOnRegistrationEntry() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: GameAudio(playback: output, scheduleIdle: { _ in }))
        game.beginRegistration()
        #expect(output.started == [10001])
        #expect(game.creatingGame)
    }

    @MainActor @Test func cdDepartureNarrationFollowsJourneyPhaseOnce() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: GameAudio(playback: output, scheduleIdle: { _ in }))
        var trip = Journey(seed: 1, edition: .macintoshCD12)
        game.trip = trip
        #expect(output.started.isEmpty)
        trip.phase = .departure; game.trip = trip
        #expect(output.started == [10002])
        game.trip = trip
        #expect(output.started == [10002] && output.stops == 0)
        trip.phase = .landmark; game.trip = trip
        #expect(!game.audio.isPlaying && output.stops == 1)
    }

    @MainActor @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func setupDialogsUseControllerAudioAndCloseBeforeNavigation(edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: audio)
        game.beginRegistration()
        #expect(game.setupDialog == .welcome)
        game.presentSetupDialog(.welcome) // Redraw/repeated presentation does not replay.
        #expect(output.started == (edition == .macintoshCD12 ? [10001] : []))
        game.dismissSetupDialog(.welcome)
        #expect(game.creatingGame && game.setupDialog == nil && !audio.isPlaying)
        game.start(profession: .banker, difficulty: .greenhorn, names: ["Test"], month: 4)
        #expect(game.trip?.phase == .outfitting)
        game.presentSetupDialog(.buyingAdvice)
        #expect(game.setupDialog == .buyingAdvice)
        game.dismissSetupDialog(.welcome) // A departed view cannot stop the new dialog.
        #expect(game.setupDialog == .buyingAdvice)
        #expect(audio.isPlaying == (edition == .macintoshCD12))
        game.dismissSetupDialog(.buyingAdvice)
        game.presentSetupDialog(.buyingAdvice)
        game.perform { try JourneyEngine.completeOutfitting([.oxen: 1, .food: 1], in: &$0) }
        #expect(game.setupDialog == .departure)
        let stops = output.stops
        output.onStop = { #expect(game.trip?.phase == .departure) }
        game.chooseDepartureMonth(4)
        output.onStop = nil
        #expect(game.trip?.phase == .landmark && game.trip?.departureMonth == 4)
        #expect(game.setupDialog == nil && !audio.isPlaying)
        #expect(output.stops == stops + (edition == .macintoshCD12 ? 1 : 0))
        audio.request(1017)
        game.dismissSetupDialog(.departure)
        #expect(audio.isPlaying && output.started.last == 1017)
        #expect(output.started == (edition == .macintoshCD12 ? [10001,10003,10003,10002,1017] : [1017]))
        #expect(game.error == nil)
    }

    @MainActor @Test(arguments: [0,1,2])
    func abandonedSetupDialogClosesOnOwnerTransition(dialog: Int) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        if dialog == 0 { game.beginRegistration() }
        else {
            var trip = Journey(seed: 1, edition: .macintoshCD12)
            if dialog == 2 { trip.phase = .departure }
            game.trip = trip
            if dialog == 1 { game.presentSetupDialog(.buyingAdvice) }
        }
        #expect(audio.isPlaying)
        game.completeDeparture(.exitGame)
        #expect(!audio.isPlaying && game.setupDialog == nil && !game.creatingGame && game.trip == nil)
        let stops = output.stops
        audio.request(2000)
        game.dismissSetupDialog(.welcome); game.dismissSetupDialog(.buyingAdvice); game.dismissSetupDialog(.departure)
        #expect(output.stops == stops && audio.isPlaying)
    }

    @MainActor @Test func setupNarrationPreservesQueueMuteAndTemporaryInactivity() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        var idle: [() -> Void] = []
        let audio = GameAudio(playback: output, scheduleIdle: { idle.append($0) })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio)
        audio.request(9007)
        game.beginRegistration()
        #expect(output.started == [9007] && output.stops == 0)
        output.callbacks.last?()
        while !idle.isEmpty { idle.removeFirst()() }
        #expect(output.started == [9007,10001])
        let completedStops = output.stops
        game.applicationActive = false; game.showingIntroduction = true; game.tick()
        game.applicationActive = true; game.showingIntroduction = false; game.tick()
        game.presentSetupDialog(.welcome)
        #expect(output.started == [9007,10001] && output.stops == completedStops)
        game.sound = false
        #expect(!audio.isPlaying)
        game.dismissSetupDialog(.welcome)
        game.start(profession: .banker, difficulty: .greenhorn, names: ["Test"], month: 4)
        game.presentSetupDialog(.buyingAdvice)
        game.sound = true
        game.presentSetupDialog(.buyingAdvice)
        #expect(output.started == [9007,10001]) // Enabling sound does not recreate the dialog.
        game.dismissSetupDialog(.buyingAdvice); game.presentSetupDialog(.buyingAdvice)
        #expect(output.started == [9007,10001,10003])
        game.trip = Journey(seed: 2, edition: .macintoshCD12)
        #expect(game.setupDialog == nil && !audio.isPlaying)
    }

    @MainActor @Test(arguments: [GameController.SetupDialog.welcome, .buyingAdvice, .departure],
                           [GameEdition.macintosh11, .macintoshCD12])
    func oldSetupActionCannotAffectAnotherOpeningOfSameDialog(dialog: GameController.SetupDialog, edition: GameEdition) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: edition,
            defaultPreferences: .init()), audio: audio)
        func open() {
            if dialog == .welcome { game.beginRegistration() }
            else {
                var trip = Journey(seed: 1, edition: edition)
                if dialog == .departure { trip.phase = .departure }
                game.trip = trip
                if dialog == .buyingAdvice { game.presentSetupDialog(.buyingAdvice) }
            }
        }
        open()
        let oldAction = game.setupDialogAction(for: dialog)
        game.completeDeparture(.exitGame)
        open()
        let currentJourney = game.trip?.id
        let stops = output.stops
        oldAction(0)
        #expect(game.setupDialog == dialog && audio.isPlaying == (edition == .macintoshCD12) && output.stops == stops)
        #expect(game.trip?.id == currentJourney)
        if dialog == .departure { #expect(game.trip?.phase == .departure) }
        let currentAction = game.setupDialogAction(for: dialog)
        currentAction(1)
        #expect(game.setupDialog == nil && !audio.isPlaying)
        if dialog == .departure { #expect(game.trip?.phase == .landmark && game.trip?.departureMonth == 4) }
        audio.request(1017)
        currentAction(1)
        #expect(audio.isPlaying && output.started.last == 1017)
    }

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
        var onStop: (() -> Void)?
        func start(_ resource: Int, completion: @escaping () -> Void) -> Bool {
            started.append(resource);callbacks.append(completion);return succeeds
        }
        func stop() { stops += 1; onStop?() }
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
    @MainActor @Test(arguments: [false, true])
    func aboutPausesUntilApplicationAndWindowAreBothActive(applicationFirst: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var tick: UInt32 = 100
        let output = Output()
        let audio = GameAudio(playback: output, scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.presentAbout()
        let action = game.aboutAction()
        #expect(output.started == [2000])
        game.gameWindowActivationChanged(false)
        tick = 103; action(.poll(showsSystemInformation: false))
        #expect(output.started == [2000])
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        game.applicationActive = false
        if applicationFirst { game.applicationActive = true }
        else { game.gameWindowActivationChanged(true) }
        action(.poll(showsSystemInformation: false))
        #expect(output.started == [2000])
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        if applicationFirst { game.gameWindowActivationChanged(true) }
        else { game.applicationActive = true }
        // Rejected polls consumed neither the clock nor a row, so this same tick is eligible.
        action(.poll(showsSystemInformation: false))
        #expect(output.started == [2000, 2000])
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 0)
        game.aboutAction()(.close)
    }

    @MainActor @Test func creditsScrollSharesAcceptedAudioPulseAndOpeningLifetime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var tick: UInt32 = 100
        let audio = GameAudio(playback: Output(), scheduleIdle: { _ in })
        let game = GameController(store: JourneyStore(directory: root, edition: .macintoshCD12,
            defaultPreferences: .init()), audio: audio, clock: { tick })
        game.presentAbout()
        let old = game.aboutAction()
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        tick = 102; old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        tick = 103; old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 0)
        tick = 1000; old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 1)
        old(.information(true))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        tick = 2000; old(.poll(showsSystemInformation: true))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        old(.information(false)); old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 0)
        old(.redraw)
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil) // redraw preserves the audio clock
        game.applicationActive = false
        tick = 2003; old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        game.applicationActive = true; old(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 0)
        old(.close); game.presentAbout()
        tick = 3000; old(.poll(showsSystemInformation: false)); old(.information(true)); old(.close)
        #expect(game.showingAbout && game.aboutCreditScroll?.sourceRow(at: 114) == nil)
        game.aboutAction()(.poll(showsSystemInformation: false))
        #expect(game.aboutCreditScroll?.sourceRow(at: 114) == 0)
        game.aboutAction()(.close)
        #expect(game.aboutCreditScroll == nil)
    }

}
