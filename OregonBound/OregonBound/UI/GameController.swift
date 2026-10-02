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
    @Published private(set) var cdAttractPage = OriginalLegendsRules.AttractPage.title
    private var cdAttract: CDAttractPresentation?
    private var attractOpening: UUID?
    private var startupAudioRequested = false
    enum AttractAction { case poll, advance, travel, load }

    /// Startup audio precedes the first page's idle-channel check. Reappearing
    /// after a journey does not replay startup or recreate an existing page.
    func showAttract() {
        guard trip == nil, !creatingGame else { return }
        if !startupAudioRequested {
            startupAudioRequested = true
            audio.request(9007)
        }
        refreshOriginalLegends()
        guard store.edition == .macintoshCD12, cdAttract == nil else { return }
        cdAttract = .init(page: cdAttractPage, sound: sound, at: clock())
        attractOpening = UUID()
        requestAttractTheme()
    }

    private func requestAttractTheme() {
        if sound, applicationActive, !fileMenu.windowInactive, !audio.isPlaying { audio.request(2000) }
    }

    func closeAttract() {
        guard cdAttract != nil else { return }
        cdAttract = nil
        attractOpening = nil
        audio.clear()
        endingTail = false
    }

    private func advanceAttract() {
        guard cdAttract != nil else { return }
        audio.clear()
        cdAttract?.advance(sound: sound, at: clock())
        attractOpening = UUID()
        cdAttractPage = cdAttract!.page
        if cdAttractPage == .legends { refreshOriginalLegends() }
        requestAttractTheme()
    }

    func attractAction() -> (AttractAction) -> Void {
        let opening = attractOpening
        return { [weak self] action in
            guard let self, let opening, self.attractOpening == opening,
                  self.applicationActive, !self.fileMenu.windowInactive,
                  !self.isOriginalModalPresented else { return }
            switch action {
            case .poll:
                if self.cdAttract?.poll(at: self.clock(), sound: self.sound, busy: self.audio.isPlaying) == true {
                    self.advanceAttract()
                }
            case .advance: self.advanceAttract()
            case .travel: self.beginRegistration()
            case .load: self.requestLoadGame(fromAttractButton: true)
            }
        }
    }

    /// The Legends Load button clears before the chooser, even on cancellation.
    /// The title's button and the File menu do not make that request.
    func prepareAttractLoadAudio() {
        if cdAttract?.page == .legends { audio.clear() }
    }

    /// CODE1's return-to-main path selects Legends. An existing Legends pane
    /// keeps its opening and partially elapsed timer (CODE10's duplicate check).
    func returnToAttractLegends() {
        guard store.edition == .macintoshCD12, trip == nil, !creatingGame else { return }
        if cdAttract?.page == .title { advanceAttract() }
        else if cdAttract == nil { cdAttractPage = .legends }
    }

    func cancelLoadGameSelection() { returnToAttractLegends() }

    func handleLoadGameFailure(_ failure: Error) {
        let cocoa = failure as NSError
        if cocoa.domain == NSCocoaErrorDomain, cocoa.code == NSUserCancelledError {
            cancelLoadGameSelection()
        } else {
            returnToAttractAfterLoadError = store.edition == .macintoshCD12 && trip == nil && !creatingGame
            error = failure.localizedDescription
        }
    }

    enum SetupDialog { case welcome, buyingAdvice, departure }
    @Published private(set) var setupDialog: SetupDialog?
    private var setupDialogID: UUID?

    private enum EndingPane { case loss, arrival, score }
    private var endingPane: EndingPane?
    private var endingJourney: UUID?
    private var endingOpening: UUID?
    private var endingTail = false
    enum EndingAction { case redraw, exitLoss, continueArrival, submitScore(name: String) }

    private func retireEnding(for incoming: Journey?) {
        if incoming != nil, endingTail { audio.clear(); endingTail = false }
        guard endingPane != nil,
              incoming?.id != endingJourney || incoming?.phase != .finished else { return }
        // Closing the arrival pane does not stop its recording. Score submission
        // clears separately; other exits can leave it playing into Legends.
        // A new journey must retire it before incoming narration starts.
        endingTail = store.edition == .macintoshCD12 && endingPane != .loss && incoming == nil && audio.isPlaying
        if store.edition == .macintoshCD12, endingPane == .loss || incoming != nil { audio.clear() }
        endingPane = nil; endingJourney = nil; endingOpening = nil
    }

    private func reconcileEnding() {
        guard !creatingGame, let trip, trip.phase == .finished else { return }
        let pane: EndingPane = !trip.won ? .loss :
            (trip.originalEndingStage == .score || trip.originalEndingStage == .completed ? .score : .arrival)
        guard endingJourney != trip.id || endingPane != pane else { return }
        endingJourney = trip.id; endingPane = pane; endingOpening = UUID()
        guard store.edition == .macintoshCD12, pane != .score else { return }
        audio.clear()
        audio.request(pane == .loss ? 9001 : 1017)
    }

    func endingAction() -> (EndingAction) -> Void {
        let opening = endingOpening
        return { [weak self] action in
            guard let self, let opening, self.endingOpening == opening,
                  self.applicationActive, !self.fileMenu.windowInactive,
                  !self.isOriginalModalPresented else { return }
            switch action {
            case .redraw:
                if self.store.edition == .macintoshCD12, self.endingPane == .loss {
                    self.audio.clear(); self.audio.request(9001)
                }
            case .exitLoss:
                if self.endingPane == .loss { self.mainMenu() }
            case .continueArrival:
                if self.endingPane == .arrival { self.showOriginalScore() }
            case .submitScore(let name):
                if self.endingPane == .score { self.submitOriginalScore(name: name) }
            }
        }
    }

    /// Logical dialog creation/close, independent of SwiftUI redraw and visibility.
    func presentSetupDialog(_ dialog: SetupDialog) {
        guard setupDialog != dialog, setupDialogIsValid(dialog) else { return }
        if let outgoing = setupDialog { dismissSetupDialog(outgoing) }
        setupDialogID = UUID()
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
        setupDialogID = nil
        setupDialog = nil
        if store.edition == .macintoshCD12 { audio.clear() }
    }

    /// Capture this opening now; an old view must not act on a later opening.
    func setupDialogAction(for dialog: SetupDialog) -> (Int) -> Void {
        let opening = setupDialogID
        return { [weak self] index in
            guard let self, let opening, self.setupDialogID == opening,
                  self.setupDialog == dialog else { return }
            if dialog == .departure { self.chooseDepartureMonth(index + 3) }
            else { self.dismissSetupDialog(dialog) }
        }
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

    @Published private(set) var cdNotification: CDNotificationRules.Selection?
    @Published private(set) var notificationPalette = CDNotificationRules.PaletteCycle()
    @Published private(set) var guidePage: Int?
    private var notificationSelection = CDNotificationRules.State()
    private var notificationTimer: CDNotificationRules.Presentation?
    private var notificationOpening: UUID?
    private var notificationJourney: UUID?
    private var notificationWasVisible = false
    enum NotificationAction { case redraw, dismiss, guide }

    private var notificationPresence: LandmarkPresence {
        guard !creatingGame, let trip,
              ![.outfitting, .departure, .finished].contains(trip.phase),
              panel == nil, memorialID == nil, actionNotice == nil, huntResult == nil,
              pendingDeparture == nil, !showingSaveTimeOut, trip.originalTradeSession == nil,
              !showingRouteDecision || trip.phase == .river else { return .closed }
        if showingRouteDecision || trip.originalRiverOutcome != nil ||
            [.hunting, .rafting].contains(trip.phase) { return .hidden }
        return .visible
    }
    var notificationPaneVisible: Bool { cdNotification != nil && notificationPresence == .visible }

    private func closeNotification() {
        guard cdNotification != nil else { return }
        notificationOpening = nil; notificationJourney = nil; notificationTimer = nil
        notificationWasVisible = false; cdNotification = nil
        audio.clear()
    }

    private func reconcileNotification() {
        guard cdNotification != nil else { return }
        guard notificationJourney == trip?.id, notificationPresence != .closed else {
            closeNotification(); return
        }
        let visible = notificationPaneVisible
        if visible && !notificationWasVisible { notificationTimer?.redraw(at: clock()) }
        notificationWasVisible = visible
    }

    /// A command consumes only the records it just created. Saved journal
    /// metadata is never replayed by assigning/loading a journey or polling UI.
    private func receiveNotifications(after entryID: Int, in value: Journey) {
        guard value.gameEdition == .macintoshCD12 else { return }
        let events = value.journal.filter { $0.id > entryID }.compactMap(\.cdNotification)
        guard !events.isEmpty else { return }
        notificationSelection.beginBatch()
        let context = CDNotificationRules.Context(weather: value.originalWeatherCategory,
            snow: Int(value.original?.weather.snow ?? 0), destination: OriginalTrailEvents.destinationIndex(value))
        for event in events { notificationSelection.receive(event, in: context) }
        // CODE17's flush requires the traveling picture or an existing notice.
        // Selection/once-per-destination guards still advance when it is absent.
        guard notificationPresence != .closed,
              cdNotification != nil || value.phase == .travel || showingTravelMap,
              let selected = notificationSelection.selected else { return }
        closeNotification()
        closeLandmark()
        cdNotification = selected
        notificationJourney = value.id; notificationOpening = UUID()
        notificationTimer = .init(openedAt: clock())
        notificationWasVisible = notificationPaneVisible
        audio.request(selected.sound)
    }

    func notificationAction() -> (NotificationAction) -> Void {
        let opening = notificationOpening
        return { [weak self] action in
            guard let self, let opening, self.notificationOpening == opening,
                  self.notificationPaneVisible, self.applicationActive,
                  !self.fileMenu.windowInactive, !self.isOriginalModalPresented else { return }
            switch action {
            case .redraw: self.notificationTimer?.redraw(at: self.clock())
            case .dismiss:
                self.closeNotification(); self.reconcileLandmark()
            case .guide:
                guard let page = self.cdNotification?.guide, page != 0 else { return }
                self.closeNotification()
                self.panel = .guide; self.guidePage = page
                self.reconcileLandmark()
            }
        }
    }

    func pollNotification() {
        guard cdNotification != nil, applicationActive, !fileMenu.windowInactive,
              !isOriginalModalPresented else { return }
        let tick = clock()
        guard let poll = notificationTimer?.poll(at: tick), poll != .none else { return }
        if notificationPaneVisible, cdNotification?.cycle == true, OriginalResources.colorMode == .color256 {
            notificationPalette.poll(at: tick)
        }
        if poll == .expired { closeNotification(); reconcileLandmark() }
    }

    @Published private(set) var cdLandmark = CDLandmarkPresentation()
    private var landmarkAudio = CDLandmarkAudio()
    // The source's last drawn weather category is initialized to zero and
    // survives journey changes, independently of whether a landmark exists.
    private var landmarkDisplayedWeather = 0
    private enum LandmarkPresence { case closed, hidden, visible }

    private var landmarkPresence: LandmarkPresence {
        guard !creatingGame, let trip,
              ![.outfitting, .departure, .travel, .finished].contains(trip.phase),
              !showingTravelMap else { return .closed }
        // Overlapping priority-one panes replace the landmark (CODE10:20a8).
        guard panel == nil, memorialID == nil, actionNotice == nil, cdNotification == nil, huntResult == nil,
              pendingDeparture == nil, !showingSaveTimeOut, trip.originalTradeSession == nil,
              !showingRouteDecision || trip.phase == .river else { return .closed }
        // Priority-three river/minigame panes hide it instead (CODE10:20b6).
        if showingRouteDecision || trip.originalRiverOutcome != nil ||
            [.hunting, .rafting].contains(trip.phase) { return .hidden }
        return .visible
    }

    var landmarkPaneVisible: Bool { landmarkPresence == .visible }

    private func applyLandmarkAudio(_ commands: [OriginalAudioQueue.Command]) {
        for command in commands {
            switch command {
            case .stop: audio.clear()
            case .start(let id): audio.request(id)
            }
        }
    }

    private func closeLandmark() {
        guard landmarkAudio.index != nil else { return }
        applyLandmarkAudio(landmarkAudio.close())
        cdLandmark = CDLandmarkPresentation()
    }

    private func reconcileLandmark(replacingJourney: Bool = false) {
        reconcileNotification()
        guard store.edition == .macintoshCD12 else { return }
        let index = trip.flatMap { trip in TrailCatalog.stops.firstIndex { $0.id == trip.locationID } }
        if replacingJourney || landmarkAudio.index != index { closeLandmark() }
        guard let trip, let index, landmarkPresence != .closed else { closeLandmark(); return }
        // An overlay can preserve an existing pane, but does not create an
        // unseen landmark beneath an activity that began elsewhere.
        guard landmarkPresence == .visible, landmarkAudio.index == nil else { return }
        landmarkAudio.open(index: index, at: clock())
        cdLandmark.update(index: index, weather: trip.originalWeatherCategory,
            snow: Int(trip.original?.weather.snow ?? 0), displayedWeather: landmarkDisplayedWeather, visible: true)
    }

    private func landmarkWeatherDidDraw() {
        guard let drawn = cdConditions.displayedSnapshot else { return }
        let weather = drawn.originalWeatherCategory
        guard weather != landmarkDisplayedWeather else { return }
        landmarkDisplayedWeather = weather
        guard let index = landmarkAudio.index, let trip else { return }
        landmarkAudio.recreate(at: clock())
        cdLandmark.update(index: index, weather: trip.originalWeatherCategory,
            snow: Int(trip.original?.weather.snow ?? 0), displayedWeather: weather, visible: true)
    }

    func pollLandmarkAudio() {
        guard store.edition == .macintoshCD12 else { return }
        applyLandmarkAudio(landmarkAudio.poll(at: clock(), visible: landmarkPaneVisible,
            active: applicationActive && !isOriginalModalPresented))
    }

    @Published var fileMenu = OriginalFileMenuRules.State()
    @Published var pendingDeparture: OriginalFileMenuRules.Departure? { didSet { reconcileLandmark() } }
    @Published var showingSaveTimeOut = false { didSet { reconcileLandmark() } }
    @Published var showingAbout = false {
        didSet {
            guard showingAbout != oldValue else { return }
            if showingAbout {
                aboutOpening = UUID()
                aboutInformation = false
                if store.edition == .macintoshCD12 {
                    let credits = GameData.preparedSession?.aboutCredits
                    aboutCreditText = credits?.text
                    aboutCreditImage = credits.flatMap { try? BitmapFont.helvetica12?.creditsRaster($0) }
                    aboutCreditScroll = try? .init(bufferHeight: aboutCreditImage?.height ?? 115)
                }
                aboutAudio = .init(openedAt: clock(), alternate: aboutAlternate)
                if store.edition == .macintoshCD12 { audio.clear(); audio.request(2000) }
            } else {
                aboutOpening = nil
                aboutAudio = nil
                aboutCreditScroll = nil
                aboutCreditImage = nil
                aboutCreditText = nil
                aboutInformation = false
                aboutAlternate = false
                if store.edition == .macintoshCD12 { audio.clear() }
            }
        }
    }
    @Published private(set) var aboutCreditScroll: OriginalAboutRules.CreditsScroll?
    @Published private(set) var aboutCreditImage: CGImage?
    @Published private(set) var aboutCreditText: String?
    private var aboutInformation = false
    private var aboutOpening: UUID?
    private var aboutAudio: OriginalAboutRules.Audio?
    private var aboutAlternate = false
    enum AboutAction { case close, poll(showsSystemInformation: Bool), information(Bool), redraw }

    private func setAboutInformation(_ information: Bool) {
        guard aboutInformation != information else { return }
        aboutInformation = information
        aboutCreditScroll?.reset()
    }

    func presentAbout(alternate: Bool = false) {
        guard !isOriginalModalPresented else { return }
        aboutAlternate = alternate
        showingAbout = true
    }

    /// View callbacks belong to one opening, including callbacks retained by a
    /// dismissed view while a new About dialog is already visible.
    func aboutAction() -> (AboutAction) -> Void {
        let opening = aboutOpening
        return { [weak self] action in
            guard let self, let opening, self.aboutOpening == opening else { return }
            switch action {
            case .close: self.showingAbout = false
            case .information(let information): self.setAboutInformation(information)
            case .redraw: self.aboutCreditScroll?.reset()
            case .poll(let information):
                self.setAboutInformation(information)
                guard self.store.edition == .macintoshCD12, self.applicationActive, !self.fileMenu.windowInactive,
                      let id = self.aboutAudio?.poll(at: self.clock(), showsSystemInformation: information) else { return }
                self.audio.request(id)
                self.aboutCreditScroll?.advance()
            }
        }
    }
    @Published var fileChooserPresented = false
    struct UserGuideOpening: Identifiable { let id = UUID() }
    @Published private(set) var userGuideOpening: UserGuideOpening?
    var canPresentUserGuide: Bool {
        store.edition == .macintoshCD12 && applicationActive && !isOriginalModalPresented
    }
    func presentUserGuide() {
        guard canPresentUserGuide else { return }
        userGuideOpening = UserGuideOpening()
        audio.clear()
    }
    func userGuideCloseAction(for opening: UUID? = nil) -> () -> Void {
        let id = opening ?? userGuideOpening?.id
        return { [weak self] in
            guard let self, let id, self.userGuideOpening?.id == id else { return }
            self.userGuideOpening = nil
        }
    }
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
            if trip != nil { closeAttract() }
            retireEnding(for: trip)
            if oldValue?.locationID != trip?.locationID { closeNotification() }
            if oldValue?.id != trip?.id || (oldValue?.phase == .rafting && trip?.phase != .rafting) {
                raftScene?.close()
                raftScene = nil
            }
            reconcileLandmark(replacingJourney: oldValue?.id != trip?.id)
            reconcileSetupDialog(replacingJourney: oldValue?.id != trip?.id)
            reconcileEnding()
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
            reconcileLandmark()
        }
    }
    private var returnToAttractAfterLoadError = false
    @Published var error: String? {
        didSet {
            if error == nil, returnToAttractAfterLoadError {
                returnToAttractAfterLoadError = false
                returnToAttractLegends()
            }
        }
    }
    @Published var running = false
    @Published var creatingGame = false {
        didSet {
            if creatingGame { closeAttract() }
            if creatingGame, endingTail { audio.clear(); endingTail = false }
            reconcileLandmark(); reconcileSetupDialog()
        }
    }
    @Published var showingRouteDecision = false { didSet { reconcileLandmark() } }
    @Published var showingIntroduction = false
    @Published var showingTravelMap = false { didSet { reconcileLandmark() } }
    @Published var memorialID: UUID? { didSet { reconcileLandmark() } }
    @Published var actionNotice: OriginalActionNotice? { didSet { reconcileLandmark() } }
    @Published var huntResult: OriginalHuntSession.Result? { didSet { reconcileLandmark() } }
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
    var applicationActive = true {
        didSet {
            // Native window activation and SwiftUI scene activation can arrive
            // in either order. The last eligible edge redraws; duplicate edges
            // and an edge arriving while the other input is inactive do not.
            if applicationActive, !oldValue { endingAction()(.redraw); notificationAction()(.redraw); aboutAction()(.redraw) }
        }
    }
    private var dayTimerCounter: UInt8 = 0
    let random: OriginalRandomStream
    let store: JourneyStore
    let audio: GameAudio
    private let clock: () -> UInt32
    var chooseGameData: (() -> Void)?
    var canChooseGameData: Bool {
        trip == nil && !creatingGame && !isOriginalModalPresented && panel == nil && pendingDeparture == nil
    }
    func requestGameData() {
        guard canChooseGameData, let chooseGameData else { return }
        closeAttract()
        applicationActive = false
        running = false
        audio.resetForSession()
        #if os(macOS)
        if OriginalApplicationDelegate.game === self { OriginalApplicationDelegate.game = nil }
        #endif
        chooseGameData()
    }

    init(store: JourneyStore = JourneyStore(), random: OriginalRandomStream? = nil, audio: GameAudio = .shared,
         clock: @escaping () -> UInt32 = { UInt32(truncatingIfNeeded: Int(ProcessInfo.processInfo.systemUptime * 60)) }) {
        self.clock = clock
        self.audio = audio
        self.store = store; self.random = random ?? .shared; hasSave = store.hasSave
        do { preferences = try store.preferences() }
        catch { self.error = "The management options could not be read. \(error.localizedDescription)" }
    }

    var isOriginalModalPresented: Bool {
        var presented = showingIntroduction || showingAbout || userGuideOpening != nil || managementPane != nil ||
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
        let lastJournalEntry = value.journal.last?.id ?? -1
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
                    // Retire the old pane before the terminal recording enters
                    // the queue; the later trip assignment also closes panes.
                    memorialID = nil
                    closeLandmark()
                    if store.edition != .macintoshCD12 {
                        audio.enqueue(OriginalDeathPresentationRules.soundResource)
                    }
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
            receiveNotifications(after: lastJournalEntry, in: value)
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
        landmarkWeatherDidDraw()
    }

    func setConditionsVisible(_ visible: Bool) {
        guard cdConditions.isVisible != visible else { return }
        if visible { showConditions() } else { cdConditions.hide() }
    }

    func pollConditions() {
        guard store.edition == .macintoshCD12 else { return }
        if cdConditions.poll(active: applicationActive, modalBlocked: isOriginalModalPresented) {
            landmarkWeatherDidDraw()
        }
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
            closeNotification()
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
        if panel == .guide { guidePage = nil }
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
        // CODE11:15ee clears before recording the score and returning to Legends.
        if store.edition == .macintoshCD12 { audio.clear() }
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
        catch { handleLoadGameFailure(error) }
    }

    func mainMenu() {
        running = false
        if trip?.canSave == true { persist(); if error != nil { return } }
        trip = nil; panel = nil; creatingGame = false; huntResult = nil; memorialID = nil; actionNotice = nil; showingTravelMap = false
        fileMenu.enterAttract(hasExportText: !retainedExportRecords.isEmpty)
        returnToAttractLegends()
    }
}
