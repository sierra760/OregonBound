import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@MainActor extension GameController {
    func gameWindowActivationChanged(_ active: Bool) {
        // These are real host-window events, even while a SwiftUI dialog covers
        // the game. Dropping an edge leaves File commands permanently stale
        // after dismissal. Modal command guards separately prevent dispatch.
        let wasInactive = fileMenu.windowInactive
        fileMenu.activateWindow(active, stage: fileStage)
        // CD CODE1:18ee clears on an actual deactivation edge, including when
        // a modal is open. Coverage by a native in-canvas dialog is not an edge.
        if store.edition == .macintoshCD12, !wasInactive, fileMenu.windowInactive { audio.clear() }
        if wasInactive, !fileMenu.windowInactive { endingAction()(.redraw); notificationAction()(.redraw) }
    }

    var fileStage: OriginalFileMenuRules.Stage {
        guard let trip else { return creatingGame ? .setup : .attract }
        if trip.phase == .finished { return .attract }
        return [.outfitting, .departure].contains(trip.phase) ? .setup : .journey
    }
    func beginRegistration() {
        retainedExportRecords = []
        fileMenu.leaveAttractViaButton()
        fileMenu.beginSetup()
        creatingGame = true
        presentSetupDialog(.welcome)
    }
    func trailLogRecords() -> [OriginalTrailLogExport.Record] {
        guard let trip, trip.phase != .finished else { return retainedExportRecords }
        return journeyLogRecords(trip)
    }
    func journeyLogRecords(_ trip: Journey) -> [OriginalTrailLogExport.Record] {
        var records: [OriginalTrailLogExport.Record] = []
        var day: Int?
        for entry in trip.journal {
            if day != entry.day {
                let date = OriginalCalendar.date(departureMonth: trip.departureMonth, daysElapsed: entry.day)
                records.append(.init(text: OriginalTrailLogExport.dateHeader(year: UInt16(date.year),
                    monthName: OriginalCalendar.monthNames[date.month - 1], day: UInt8(date.day))))
                day = entry.day
            }
            records.append(.init(text: entry.text))
        }
        return records
    }
    func buildEndingReport(_ trip: Journey) {
        retainedExportRecords = journeyLogRecords(trip) + OriginalEndingReport.arrival(won: trip.won)
        if trip.won, trip.originalEndingStage == .score || trip.originalEndingStage == .completed {
            retainedExportRecords += OriginalEndingReport.score(survivors: trip.livingMembers.count,
                health: trip.healthLabel, score: JourneyEngine.score(trip))
        }
    }
    func requestDeparture(_ departure: OriginalFileMenuRules.Departure) {
        guard !isOriginalModalPresented, fileMenu.permits(departure == .quit ? .quit : .exitGame) else { return }
        if OriginalFileMenuRules.requestDeparture(stage: fileStage) == .askToSave {
            panel = nil; actionNotice = nil; memorialID = nil; showingRouteDecision = false
            pendingDeparture = departure
        } else { completeDeparture(departure) }
    }
    func answerDeparture(_ choice: OriginalFileMenuRules.Choice) {
        guard let departure = pendingDeparture else { return }
        pendingDeparture = nil
        switch OriginalFileMenuRules.respond(choice, moving: (trip?.original?.flags ?? 0) & 2 != 0) {
        case .depart: completeDeparture(departure)
        case .showTimeOutRequired: showingSaveTimeOut = true
        case .chooseSaveFile: requestManualSave(after: departure)
        default: break
        }
    }
    func completeDeparture(_ departure: OriginalFileMenuRules.Departure) {
        if let trip, fileStage == .journey { retainedExportRecords = journeyLogRecords(trip) }
        // No means no explicit file write. The private autosave is separate.
        running = false; trip = nil; panel = nil; creatingGame = false
        huntResult = nil; memorialID = nil; actionNotice = nil; showingTravelMap = false
        pendingDeparture = nil; showingSaveTimeOut = false
        fileMenu.enterAttract(hasExportText: !retainedExportRecords.isEmpty)
        returnToAttractLegends()
        #if os(macOS)
        if departure == .quit {
            OriginalApplicationDelegate.allowTermination = true
            NSApp.terminate(nil)
        }
        #endif
    }
    func saveManually(to url: URL) throws {
        guard let trip, fileMenu.permits(.save), trip.canSave else { throw GameRuleError("This game cannot be saved now.") }
        guard (trip.original?.flags ?? 0) & 2 == 0 else { throw GameRuleError(OriginalFileMenuRules.timeOutRequired) }
        var snapshot = trip
        snapshot.randomState = random.seed
        try store.save(snapshot, to: url)
    }
    func exportTrailLog(to url: URL) throws {
        let data = try OriginalTrailLogExport.data(records: trailLogRecords())
        try data.write(to: url, options: .atomic)
        #if os(macOS)
        try FileManager.default.setAttributes([.hfsTypeCode: OriginalTrailLogExport.finderType,
            .hfsCreatorCode: OriginalTrailLogExport.finderCreator], ofItemAtPath: url.path)
        #endif
    }
    @discardableResult
    func prepareLoadGame(fromAttractButton: Bool) -> Bool {
        guard !isOriginalModalPresented, fileMenu.permits(.load) else { return false }
        if fromAttractButton {
            prepareAttractLoadAudio()
            fileMenu.leaveAttractViaButton()
        }
        return true
    }
    func requestLoadGame(fromAttractButton: Bool = false) {
        guard prepareLoadGame(fromAttractButton: fromAttractButton) else { return }
        #if os(macOS)
        let chooser = NSOpenPanel()
        chooser.directoryURL = store.directory
        chooser.canChooseDirectories = false; chooser.allowsMultipleSelection = false
        chooser.allowedContentTypes = [.json]
        presentFileChooser(chooser) { [weak self] result in
            guard result == .OK, let url = chooser.url else {
                self?.cancelLoadGameSelection()
                return
            }
            self?.resume(from: url)
        }
        #else
        showingLoadDialog = true
        #endif
    }
    func requestManualSave(after departure: OriginalFileMenuRules.Departure? = nil) {
        guard !isOriginalModalPresented, fileMenu.permits(.save) else { return }
        guard OriginalFileMenuRules.saveAction(moving: (trip?.original?.flags ?? 0) & 2 != 0) == .chooseSaveFile else {
            showingSaveTimeOut = true; return
        }
        #if os(macOS)
        let chooser = NSSavePanel()
        chooser.message = "Save current game as:"
        chooser.nameFieldStringValue = ""
        // Transitional native archive; original ORDC import/export is separately audited.
        chooser.allowedContentTypes = [.json]
        presentFileChooser(chooser) { [weak self] result in
            guard let self, result == .OK, let url = chooser.url else { return }
            do {
                try self.saveManually(to: url)
                if let departure { self.completeDeparture(departure) }
            } catch { self.error = error.localizedDescription }
        }
        #else
        guard var trip else { return }
        trip.randomState = random.seed
        do {
            try store.validate(trip)
            let data = try JSONEncoder().encode(SavedJourney(format: "OregonBound", version: 1, journey: trip))
            exportDocument = OriginalTransferDocument(data: data)
            exportFilename = ""; exportIsJourney = true; exportDeparture = departure
            showingExportDialog = true
        } catch { self.error = error.localizedDescription }
        #endif
    }
    func requestExportTrailLog() {
        guard !isOriginalModalPresented, fileMenu.permits(.exportLog) else { return }
        #if os(macOS)
        let chooser = NSSavePanel()
        chooser.message = OriginalTrailLogExport.chooserPrompt
        chooser.nameFieldStringValue = OriginalTrailLogExport.suggestedFilename
        presentFileChooser(chooser) { [weak self] result in
            guard let self, result == .OK, let url = chooser.url else { return }
            do {
                try self.exportTrailLog(to: url)
                if self.fileStage == .journey { self.retainedExportRecords = [] }
            }
            catch { self.error = error.localizedDescription }
        }
        #else
        do {
            exportDocument = OriginalTransferDocument(data: try OriginalTrailLogExport.data(records: trailLogRecords()))
            exportFilename = OriginalTrailLogExport.suggestedFilename; exportIsJourney = false; exportDeparture = nil
            showingExportDialog = true
        } catch { self.error = error.localizedDescription }
        #endif
    }

    #if os(macOS)
    /// The transitional JSON/text picker belongs to the game window. A modeless
    /// `begin` can leave it behind the game while our modal gate blocks all input.
    private func presentFileChooser(_ chooser: NSSavePanel,
                                    completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            error = "The game window is not available. Reopen it and try again."
            return
        }
        fileChooserPresented = true
        chooser.beginSheetModal(for: window) { [weak self] result in
            self?.fileChooserPresented = false
            completion(result)
        }
    }
    #endif
}

#if os(macOS)
@MainActor final class OriginalApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var game: GameController?
    static var allowTermination = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.allowTermination, let game = Self.game else { return .terminateNow }
        guard !game.isOriginalModalPresented, game.fileMenu.permits(.quit) else { return .terminateCancel }
        if game.fileStage == .journey { game.requestDeparture(.quit); return .terminateCancel }
        return .terminateNow
    }
}
#endif
