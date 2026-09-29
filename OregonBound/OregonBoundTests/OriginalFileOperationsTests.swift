import Foundation
import Testing
@testable import OregonBound

struct OriginalFileOperationsTests {
    @Test @MainActor func focusRestoredDuringModalDoesNotLeaveLoadDisabledAfterClosing() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        game.gameWindowActivationChanged(false)
        game.managementPane = .timeOptions
        game.gameWindowActivationChanged(true)
        #expect(!game.prepareLoadGame(fromAttractButton: true))
        game.managementPane = nil
        #expect(game.canUseGameMenus)
        #expect(game.prepareLoadGame(fromAttractButton: true))
    }

    @Test @MainActor func focusLostDuringModalStaysInactiveAfterClosing() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        game.showingLegendsManagement = true
        game.gameWindowActivationChanged(false)
        game.showingLegendsManagement = false
        #expect(!game.canUseGameMenus)
        #expect(!game.prepareLoadGame(fromAttractButton: true))
        game.gameWindowActivationChanged(true)
        #expect(game.prepareLoadGame(fromAttractButton: true))
    }

    @Test @MainActor func duplicateActiveNotificationDuringModalPreservesActivityLocks() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1); trip.phase = .hunting
        game.trip = trip; game.fileMenu.beginJourney(); game.fileMenu.beginBlockingActivity()
        let before = game.fileMenu
        game.showingAbout = true
        game.gameWindowActivationChanged(true)
        game.showingAbout = false
        #expect(game.fileMenu == before)
        #expect(!game.fileMenu.permits(.save) && !game.fileMenu.permits(.quit))
    }

    @Test @MainActor func noExitsWithoutWritingOverAnExistingManualSaveAndKeepsJournalExport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        let original = Journey(seed: 1)
        try store.save(original)
        let before = try Data(contentsOf: store.saveURL)
        let game = GameController(store: store, random: OriginalRandomStream(seed: 2))
        var trip = Journey(seed: 2); trip.phase = .travel; trip.record("You decided to continue.")
        game.trip = trip; game.fileMenu.beginJourney()
        game.requestDeparture(.exitGame)
        #expect(game.pendingDeparture == .exitGame)
        game.answerDeparture(.no)
        #expect(game.trip == nil && game.fileMenu.permits(.load))
        #expect(game.fileMenu.permits(.exportLog))
        #expect(game.trailLogRecords().last?.text == "You decided to continue.")
        #expect(try Data(contentsOf: store.saveURL) == before)
    }
    @Test @MainActor func finishedJourneyQuitsDirectlyWithoutOfferingADisabledSave() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1); trip.phase = .finished
        game.trip = trip; game.fileMenu.beginJourney(); game.fileMenu.beginEnding()
        #expect(game.fileMenu.permits(.quit) && !game.fileMenu.permits(.save))
        #expect(game.fileStage == .attract)
        #expect(OriginalFileMenuRules.requestDeparture(stage: game.fileStage) == .depart)
    }
    @Test @MainActor func originalModalDialogsSuspendModelPulses() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41); trip.phase = .travel
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        JourneyEngine.resumeTravel(in: &trip)
        game.trip = trip; game.showingAbout = true
        for _ in 0..<4 { game.tick() }
        #expect(game.trip == trip)
        game.showingAbout = false; game.managementPane = .timeOptions
        for _ in 0..<4 { game.tick() }
        #expect(game.trip == trip)
        game.managementPane = nil; game.fileChooserPresented = true
        for _ in 0..<4 { game.tick() }
        #expect(game.trip == trip)
        game.fileChooserPresented = false
        for _ in 0..<4 { game.tick() }
        #expect(game.trip?.daysElapsed == 1)
    }
    @Test @MainActor func onlyAttractButtonLoadDisablesRetainedExport() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        game.retainedExportRecords = [.init(text: "Your Score = 123")]
        game.fileMenu.enterAttract(hasExportText: true)
        #expect(game.prepareLoadGame(fromAttractButton: false))
        #expect(game.fileMenu.permits(.exportLog))
        #expect(game.prepareLoadGame(fromAttractButton: true))
        #expect(!game.fileMenu.permits(.exportLog))
    }
    @Test @MainActor func endingReportAddsOriginalSuffixAndSurvivesReturningToTitle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1); trip.phase = .travel; trip.record("You decided to continue.")
        game.trip = trip; game.fileMenu.beginJourney()
        game.perform { JourneyEngine.finish(&$0, won: true, reason: "Internal outcome") }
        #expect(game.trip?.journal.last?.text == "You decided to continue.")
        game.showOriginalScore()
        let records = game.trailLogRecords()
        let data = try OriginalTrailLogExport.data(records: records)
        let text = String(data: data, encoding: .macOSRoman)!
        #expect(text.contains("You made it to the Willamette Valley.\r"))
        #expect(text.contains("5 people arrived in good health.\r"))
        #expect(text.contains("Your Score = "))
        #expect(!text.contains("Internal outcome"))
        game.mainMenu()
        #expect(try OriginalTrailLogExport.data(records: game.trailLogRecords()) == data)
    }
    @Test @MainActor func movingSaveIsRejectedButMenuRemainsEnabled() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1); trip.phase = .travel
        JourneyEngine.resumeTravel(in: &trip)
        game.trip = trip; game.fileMenu.beginJourney()
        #expect(game.fileMenu.permits(.save))
        game.requestManualSave()
        #expect(game.showingSaveTimeOut)
        #expect(game.trip == trip)
        game.showingSaveTimeOut = false
        game.requestDeparture(.exitGame); game.answerDeparture(.yes)
        #expect(game.pendingDeparture == nil && game.showingSaveTimeOut)
        #expect(game.trip == trip)
    }
    @Test @MainActor func manualSaveUsesSelectedFileAndExportUsesMacRomanCR() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 19))
        var trip = Journey(seed: 1); trip.phase = .travel
        trip.record("You decided to continue.")
        game.trip = trip; game.fileMenu.beginJourney()
        let manual = folder.appendingPathComponent("Chosen.json")
        try game.saveManually(to: manual)
        #expect(!game.store.hasSave)
        #expect(try game.store.load(from: manual).randomState == 19)
        let log = folder.appendingPathComponent("Trail Log")
        try game.exportTrailLog(to: log)
        let expected = "• April 1, 1848 •\rYou decided to continue.\r".data(using: .macOSRoman)!
        #expect(try Data(contentsOf: log) == expected)
    }
    @Test @MainActor func blockingActivitiesDisableAndRestoreFileActions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1); trip.phase = .travel; trip.inventory[.bullets] = 100
        game.trip = trip; game.fileMenu.beginJourney()
        game.startHunt()
        #expect(game.trip?.phase == .hunting)
        #expect(!game.fileMenu.permits(.save) && !game.fileMenu.permits(.quit))
        game.perform { try JourneyEngine.finishHunt(food: 0, shots: 0, in: &$0) }
        #expect(game.fileMenu.permits(.save) && game.fileMenu.permits(.quit))
    }
}
