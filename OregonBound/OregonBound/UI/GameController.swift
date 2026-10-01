import SwiftUI
#if os(macOS)
import AppKit
#endif

enum GamePanel: String, Identifiable {
    case shop = "General Store", supplies = "Supplies", map = "Trail Map", guide = "Guidebook", talk = "Talk", trade = "Trade", rest = "Rest", conditions = "Conditions", journal = "Trail Journal", scores = "Hall of Fame", help = "How to Play"
    case pace = "Pace", rations = "Rations"
    var id: String { rawValue }
    var usesTrailPane: Bool { [.pace, .rations, .rest, .supplies, .guide, .trade, .talk].contains(self) }
}

@MainActor final class GameController: ObservableObject {
    enum SetupDialog { case welcome, buyingAdvice, departure }
    @Published private(set) var setupDialog: SetupDialog?

    /// Logical dialog creation/close, independent of SwiftUI redraw and visibility.
    func presentSetupDialog(_ dialog: SetupDialog) {
        guard setupDialog != dialog, setupDialogIsValid(dialog) else { return }
        if let outgoing = setupDialog { dismissSetupDialog(outgoing) }
        setupDialog = dialog
        guard store.edition == .macintoshCD12 else { return }
        switch dialog {
        case .welcome: audio.request(10001)
        case .departure: audio.request(10002)
        case .buyingAdvice: audio.request(10003)
        }
    }

    func dismissSetupDialog(_ dialog: SetupDialog) {
        guard setupDialog == dialog else { return }
        setupDialog = nil
        if store.edition == .macintoshCD12 { audio.clear() }
    }

    func chooseDepartureMonth(_ month: Int) {
        guard setupDialog == .departure, trip?.phase == .departure else { return }
        // The original month callback clears before changing the world.
        dismissSetupDialog(.departure)
        perform { try JourneyEngine.chooseDeparture(month: month, in: &$0) }
    }

    private func setupDialogIsValid(_ dialog: SetupDialog) -> Bool {
        switch dialog {
        case .welcome: return creatingGame
        case .buyingAdvice: return !creatingGame && trip?.phase == .outfitting
        case .departure: return !creatingGame && trip?.phase == .departure
        }
    }

    private func reconcileSetupDialog(replacingJourney: Bool = false) {
        if let dialog = setupDialog, replacingJourney || !setupDialogIsValid(dialog) {
            dismissSetupDialog(dialog)
        }
        if !creatingGame && trip?.phase == .departure { presentSetupDialog(.departure) }
    }

    @Published var fileMenu = OriginalFileMenuRules.State()
    @Published var pendingDeparture: OriginalFileMenuRules.Departure?
    @Published var showingSaveTimeOut = false
    @Published var showingAbout = false
    @Published var fileChooserPresented = false
    #if os(iOS)
    @Published var showingLoadDialog = false
    @Published var showingExportDialog = false
    var exportDocument: OriginalTransferDocument?
    var exportFilename = ""
    var exportIsJourney = false
    var exportDeparture: OriginalFileMenuRules.Departure?
    #endif
    var retainedExportRecords: [OriginalTrailLogExport.Record] = []
    @Published var trip: Journey? {
        didSet {
            if oldValue?.id != trip?.id || (oldValue?.phase == .rafting && trip?.phase != .rafting) {
                raftScene?.close()
                raftScene = nil
            }
            reconcileSetupDialog(replacingJourney: oldValue?.id != trip?.id)
        }
    }
    private weak var raftScene: OriginalRaftScene?

    func registerRaftScene(_ scene: OriginalRaftScene) {
        guard trip?.phase == .rafting else { scene.close(); return }
        if raftScene !== scene { raftScene?.close() }
        raftScene = scene
    }
    @Published private(set) var cdConditions = CDConditionsPresentation()
    @Published var panel: GamePanel? {
        didSet {
            // CD pane-close callbacks run before the incoming pane initializes.
            // Keep this synchronous: a disappearing SwiftUI view can run later
            // and otherwise stop the new conversation's recording.
            if store.edition == .macintoshCD12,
               oldValue == .talk || (oldValue == .guide && panel != .guide) {
                audio.clear()
            }
        }
    }
    @Published var error: String?
    @Published var running = false
    @Published var creatingGame = false { didSet { reconcileSetupDialog() } }
    @Published var showingRouteDecision = false
    @Published var showingIntroduction = false
    @Published var showingTravelMap = false
    @Published var memorialID: UUID?
    @Published var actionNotice: OriginalActionNotice?
    @Published var huntResult: OriginalHuntSession.Result?
    @Published var talkSelection: OriginalTalkRules.Selection?
    private var talkState = OriginalTalkRules.State()
    @Published var hasSave: Bool
    @Published var scores: [HighScore] = []
    @Published var legends = OriginalEndingPresentation.initialLegends
    @Published var showingLegendsManagement = false
    @Published var preferences = OriginalPreferences.Configuration()
    @Published var management = OriginalPreferences.ManagementSession()
    @Published var managementPane: OriginalPreferences.ManagementItem?
    @Published var sound = true { didSet { audio.enabled = sound } }
    var applicationActive = true
    private var dayTimerCounter: UInt8 = 0
    let random: OriginalRandomStream
    let store: JourneyStore
    let audio: GameAudio
    var chooseGameData: (() -> Void)?
    var canChooseGameData: Bool {
        trip == nil && !creatingGame && !isOriginalModalPresented && panel == nil && pendingDeparture == nil
    }
    func requestGameData() {
        guard canChooseGameData, let chooseGameData else { return }
        applicationActive = false
        running = false
        audio.resetForSession()
        #if os(macOS)
        if OriginalApplicationDelegate.game === self { OriginalApplicationDelegate.game = nil }
        #endif
        chooseGameData()
    }

    init(store: JourneyStore = JourneyStore(), random: OriginalRandomStream? = nil, audio: GameAudio = .shared) {
        self.audio = audio
        self.store = store; self.random = random ?? .shared; hasSave = store.hasSave
        do { preferences = try store.preferences() }
        catch { self.error = "The management options could not be read. \(error.localizedDescription)" }
    }

    var isOriginalModalPresented: Bool {
        var presented = showingIntroduction || showingAbout || managementPane != nil ||
            showingLegendsManagement || error != nil || fileChooserPresented
        #if os(iOS)
        presented = presented || showingLoadDialog || showingExportDialog
        #endif
        return presented
    }

    var canUseGameMenus: Bool { fileMenu.permitsGameMenus && !isOriginalModalPresented }
    func requestIntroduction() {
        guard canUseGameMenus else { return }
        showingIntroduction = true
    }
    func setSoundFromMenu(_ enabled: Bool) {
        guard canUseGameMenus else { return }
        sound = enabled
    }

    func start(profession: Profession, difficulty: Difficulty, names: [String], month: Int) {
        trip = Journey(profession: profession, difficulty: difficulty, names: names, departureMonth: month, seed: random.seed, edition: store.edition)
        trip?.originalTiming = preferences.beginJourney()
        fileMenu.beginSetup()
        creatingGame = false
        showingTravelMap = false; memorialID = nil; actionNotice = nil
        panel = nil
        running = false
        huntResult = nil
        persist()
    }

    func perform(_ action: (inout Journey) throws -> Void) {
        guard var value = trip else { return }
        value.randomState = random.seed
        let oldPhase = value.phase
        let wasBlocking = [.hunting, .rafting].contains(value.phase) || value.originalRiverOutcome != nil
        let oldLocation = value.locationID
        let oldLiving = value.livingMembers.count
        do {
            try action(&value)
            random.seed = value.randomState
            if value.phase != oldPhase || value.locationID != oldLocation {
                showingTravelMap = value.originalMapSuppressedLandmarkID == value.locationID
            }
            // Close outgoing narration before queuing sounds for the new phase.
            if value.phase != oldPhase { panel = nil; showingRouteDecision = false }
            if value.livingMembers.count < oldLiving && oldPhase != .rafting {
                value.original?.flags &= ~2
                if value.livingMembers.isEmpty {
                    memorialID = nil
                    audio.enqueue(OriginalDeathPresentationRules.soundResource)
                } else { memorialID = UUID() }
            }
            let isBlocking = [.hunting, .rafting].contains(value.phase) || value.originalRiverOutcome != nil
            if oldPhase == .departure && value.phase != .departure { fileMenu.beginJourney() }
            if !wasBlocking && isBlocking { fileMenu.beginBlockingActivity() }
            if wasBlocking && !isBlocking { fileMenu.endBlockingActivity() }
            if value.phase == .finished {
                fileMenu.beginEnding()
                if oldPhase != .finished { buildEndingReport(value) }
            }
            trip = value
            // CODE17:2c8e publishes Oregon arrival before the enclosing timer.
            // Its terminal receiver copies the world without advancing the
            // Conditions revision. Losses and ordinary commands do not send it.
            if value.gameEdition == .macintoshCD12, oldPhase != .finished,
               value.phase == .finished, value.won {
                cdConditions.publish(value)
            }
            running = value.phase == .travel && (value.original?.flags ?? 0) & 2 != 0
            if value.canSave { persist() }
        } catch { self.error = error.localizedDescription; running = false }
    }

    func tick() {
        guard applicationActive, !isOriginalModalPresented, var trip,
              [.travel, .landmark, .river, .fork, .hunting, .rafting].contains(trip.phase),
              trip.originalTradeSession == nil else { return }
        // CODE17 publishes at the end of every active model pulse, even
        // when its day threshold was not reached or travel is stopped.
        defer {
            if let updated = self.trip, updated.gameEdition == .macintoshCD12 {
                cdConditions.publish(updated)
            }
        }
        if trip.gameEdition == .macintoshCD12 {
            JourneyEngine.refreshWagonWeight(in: &trip)
            self.trip = trip
        }
        // Each world keeps its initial speed (4 for Medium).
        // Bit1 marks an active original world; stored state keeps action bits.
        guard OriginalActionScheduler.timerPulse(counter: &dayTimerCounter, threshold: trip.timing.timerThreshold,
                                                 flags: (trip.original?.flags ?? 0) | 1 | (trip.originalRiverOutcome != nil ? 16 : 0)) else { return }
        perform { JourneyEngine.advanceActionDay(in: &$0) }
    }

    func showConditions() {
        guard let trip, trip.gameEdition == .macintoshCD12 else { return }
        cdConditions.show(trip)
    }

    func setConditionsVisible(_ visible: Bool) {
        guard cdConditions.isVisible != visible else { return }
        if visible { showConditions() } else { cdConditions.hide() }
    }

    func pollConditions() {
        guard store.edition == .macintoshCD12 else { return }
        cdConditions.poll(active: applicationActive, modalBlocked: isOriginalModalPresented)
    }

    func continueJourney() {
        guard trip?.originalTradeSession == nil, trip?.originalRiverOutcome == nil, huntResult == nil else { return }
        if !running, trip?.canCamp == true {
            var missing: Supply?
            perform { missing = OriginalWagonContinuation.prepare(&$0) }
            if let missing { error = OriginalWagonContinuation.message(for: missing); return }
        }
        guard let trip else { return }
        if trip.phase == .travel {
            let wasRunning = running
            perform {
                if wasRunning { JourneyEngine.pauseTravel(in: &$0) }
                else { JourneyEngine.resumeTravel(in: &$0) }
                $0.record(wasRunning ? "You decided to call a time out." : "You decided to continue.")
            }
            if !wasRunning { dayTimerCounter = 0 }
        } else {
            perform { try JourneyEngine.depart(&$0) }
            running = self.trip?.phase == .travel
            showingRouteDecision = self.trip?.phase == .fork
        }
    }

    func crossRiver(_ method: CrossingMethod) {
        running = false
        perform { try JourneyEngine.beginCrossing(method, in: &$0) }
        if error == nil { showingRouteDecision = false; panel = nil }
    }

    func startHunt() {
        guard let trip, trip.canCamp, !trip.livingMembers.isEmpty else { return }
        let decision = trip.huntEligibility
        switch decision {
        case .allowed:
            actionNotice = nil
            perform { try JourneyEngine.beginHunt(&$0) }
        case .severeWeather, .occupiedLandmark, .noBullets:
            let names = OriginalResources.strings(3002)
            let destination = trip.phase == .travel ? trip.destinationID : trip.locationID
            let index = TrailCatalog.stops.firstIndex { $0.id == destination } ?? 0
            let name = names.indices.contains(index) ? names[index] : trip.location.name
            if let text = decision.notice(landmarkName: name) {
                panel = nil; memorialID = nil; showingRouteDecision = false
                actionNotice = .init(text: text, ticks: decision == .occupiedLandmark ? nil : 300)
            }
        case .silentBusy: break
        case .beepBusy:
            #if os(macOS)
            NSSound.beep()
            #endif
        }
    }
    func dismissActionNotice() {
        actionNotice = nil
        showingTravelMap = trip?.phase == .travel ||
            (trip?.originalMapSuppressedLandmarkID != nil && trip?.originalMapSuppressedLandmarkID == trip?.locationID)
    }

    func finishOriginalHunt(_ result: OriginalHuntSession.Result) {
        guard trip?.phase == .hunting else { return }
        var settled = result
        perform { settled = try JourneyEngine.finishHunt(result: result, in: &$0) }
        if error == nil { huntResult = settled }
    }

    func prepareCrossingResult() {
        guard trip?.phase == .river, trip?.originalRiverOutcome?.isPrepared == false else { return }
        perform { JourneyEngine.prepareCrossingResult(in: &$0) }
    }

    func finishCrossing() {
        guard let result = trip?.originalRiverOutcome, result.isPrepared else { return }
        perform { JourneyEngine.completeCrossing(in: &$0) }
        if error == nil && result.drownedMembers.isEmpty && trip?.phase == .landmark {
            perform { try JourneyEngine.depart(&$0) }
        }
        running = error == nil && trip?.phase == .travel
    }

    func open(_ panel: GamePanel) {
        guard trip?.originalRiverOutcome == nil, trip?.originalTradeSession == nil, huntResult == nil else { return }
        // CODE6:1c6c toggles stopped-landmark pictures and wagon/map panes.
        // A just-crossed river suppresses its picture until the next destination.
        if panel == .map {
            let forced = trip?.phase == .travel || trip?.locationID == "oregon" ||
                (trip?.originalMapSuppressedLandmarkID != nil && trip?.originalMapSuppressedLandmarkID == trip?.locationID)
            showingTravelMap = forced || (self.panel == nil && memorialID == nil && !showingRouteDecision && !showingTravelMap)
            self.panel = nil; showingRouteDecision = false; memorialID = nil; actionNotice = nil
            return
        }
        if panel.usesTrailPane { memorialID = nil; actionNotice = nil }
        if panel == .scores {
            do { scores = try store.scores() }
            catch { self.error = "The Hall of Fame could not be read. \(error.localizedDescription)"; return }
        }
        if panel == .talk {
            guard let trip, let selection = OriginalTalkRules.open(trip: trip, state: &talkState) else { return }
            talkSelection = selection
        }
        self.panel = panel
        if panel == .talk, let sound = talkSelection?.soundResourceID { audio.request(sound) }
    }

    func persist() {
        guard var snapshot = trip, snapshot.canSave else { return }
        snapshot.randomState = random.seed
        do { try store.save(snapshot); hasSave = true }
        catch { self.error = "Your progress could not be saved. \(error.localizedDescription)"; running = false }
    }

    func openManagement(_ item: OriginalPreferences.ManagementItem) {
        guard canUseGameMenus, management.permits(item) else { return }
        if item == .enableDisable && management.enabled { management.disable(); managementPane = nil; return }
        if item == .clearLegends { openLegendsManagement(); return }
        managementPane = item
    }
    func enableManagement(password: String) -> Bool {
        guard management.enable(password: password, configuration: preferences) else { return false }
        managementPane = nil
        return true
    }
    func savePreferences(_ configuration: OriginalPreferences.Configuration) throws {
        guard management.enabled else { return }
        try store.savePreferences(configuration)
        preferences = configuration
        managementPane = nil
    }
    func saveTiming(_ timing: OriginalPreferences.Timing) throws {
        guard management.permits(.timeOptions) else { return }
        var configuration = preferences
        configuration.timing = timing
        try savePreferences(configuration)
    }
    func openLegendsManagement() {
        guard management.permits(.clearLegends) else { return }
        refreshOriginalLegends()
        if error == nil { showingLegendsManagement = true }
    }
    func restoreOriginalLegends() throws -> [OriginalEndingPresentation.Legend] {
        guard management.permits(.clearLegends) else { throw GameRuleError("Enable Management first.") }
        try store.restoreOriginalLegends()
        legends = try store.legends()
        scores = try store.scores()
        return legends
    }
    func finishLegendsManagement(removing entries: [OriginalEndingPresentation.Legend]) throws {
        guard management.permits(.clearLegends) else { throw GameRuleError("Enable Management first.") }
        try store.removeLegends(entries)
        legends = try store.legends()
        scores = try store.scores()
        showingLegendsManagement = false
    }

    func refreshOriginalLegends() {
        do { scores = try store.scores(); legends = try store.legends() }
        catch { self.error = "The List of Legends could not be read. \(error.localizedDescription)" }
    }

    func showOriginalScore() {
        guard trip?.phase == .finished, trip?.won == true else { return }
        do { scores = try store.scores(); legends = try store.legends() }
        catch { self.error = "The List of Legends could not be read. \(error.localizedDescription)"; return }
        if trip?.originalEndingStage != .score, let trip {
            retainedExportRecords += OriginalEndingReport.score(survivors: trip.livingMembers.count,
                health: trip.healthLabel, score: JourneyEngine.score(trip))
        }
        perform { $0.originalEndingStage = .score }
    }

    func submitOriginalScore(name: String) {
        guard let trip, trip.phase == .finished, trip.won else { return }
        do {
            let legends = try store.legends(excluding: trip.id)
            if OriginalEndingPresentation.insertionIndex(score: JourneyEngine.score(trip), legends: legends) != nil {
                let entered = name.isEmpty ? "The Unknown Traveler" : String(name.prefix(26))
                try store.recordScore(trip, name: entered)
            }
            perform { $0.originalEndingStage = .completed }
            if error == nil { mainMenu() }
        } catch { self.error = "The List of Legends could not be saved. \(error.localizedDescription)" }
    }

    func resume(from source: URL? = nil) {
        do {
            let saved = try store.load(from: source)
            var paused = saved
            JourneyEngine.pauseTravel(in: &paused)
            paused.randomState = random.seed
            trip = paused
            if paused.gameEdition == .macintoshCD12 {
                cdConditions.publish(paused)
                if cdConditions.isVisible { cdConditions.show(paused) }
            }
            fileMenu.beginJourney()
            if paused.phase == .finished { fileMenu.beginEnding() }
            else if paused.originalRiverOutcome != nil { fileMenu.beginBlockingActivity() }
            showingTravelMap = paused.originalMapSuppressedLandmarkID == paused.locationID
            memorialID = nil; actionNotice = nil
            creatingGame = false
            panel = saved.originalTradeSession == nil ? nil : .trade
            running = false
            huntResult = nil
            dayTimerCounter = 0
            if saved.phase == .finished {
                scores = try store.scores(); legends = try store.legends()
                buildEndingReport(saved)
            }
        }
        catch { self.error = error.localizedDescription }
    }

    func mainMenu() {
        running = false
        if trip?.canSave == true { persist(); if error != nil { return } }
        trip = nil; panel = nil; creatingGame = false; huntResult = nil; memorialID = nil; actionNotice = nil; showingTravelMap = false
        fileMenu.enterAttract(hasExportText: !retainedExportRecords.isEmpty)
    }
}
