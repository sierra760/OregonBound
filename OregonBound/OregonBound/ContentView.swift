import SwiftUI
import Combine
import UniformTypeIdentifiers

let trailPaper = Color(red: 1, green: 0.98, blue: 0.86)

struct TrailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .serif))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(configuration.isPressed ? Color.yellow.opacity(0.6) : Color.white)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// An edition is adopted before constructing its controller and resource views.
struct ContentView: View {
    @StateObject private var dataState = GameDataState()
    var body: some View {
        ZStack {
            if dataState.isReady {
                GameRootView(chooseGameData: dataState.showLibrary).id(dataState.sessionID)
            } else {
                GameDataSetupView(state: dataState)
                    .frame(minWidth: 512, minHeight: 322)
            }
        }
        #if os(macOS)
        .background(OriginalWindowGeometry(canvas: OriginalWindowGeometry.minimumSize))
        #endif
    }
}

struct GameRootView: View {
    var chooseGameData: () -> Void = {}
    @StateObject private var game = GameController()
    @State private var showingWelcome = false
    @State private var managementAlert: OriginalManagementAlerts.Presentation?
    @State private var managementAlertID = UUID()
    @State private var managementAlertReady = false
    @State private var legendsConfirmationPresented = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: Double(OriginalActionScheduler.timerIntervalTicks) / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth: CGFloat = 512
            let canvasHeight: CGFloat = 322
            // The window keeps the 512x322 aspect ratio, so the artwork fills it
            // at any size. Snap to the backing grid so pixel rows stay uniform.
            let fit = min(geometry.size.width / canvasWidth, geometry.size.height / canvasHeight)
            let scale = max(1 / displayScale, floor(fit * canvasWidth * displayScale) / (canvasWidth * displayScale))
            ZStack {
                Color.black
                gameSurface.environment(\.originalModalDispatchBlocked, game.isOriginalModalPresented)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .background(trailPaper).foregroundStyle(.black)
                    .font(.system(size: 12, design: .serif))
                    .buttonStyle(TrailButtonStyle()).controlSize(.mini)
                    .environment(\.colorScheme, .light)
                    .scaleEffect(scale)
                    .frame(width: canvasWidth * scale, height: canvasHeight * scale)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(timer) { _ in game.tick() }
        .onAppear {
            game.chooseGameData = chooseGameData
            BundleAssets.validateManifest()
            GameAudio.shared.request(9007)
            #if os(macOS)
            OriginalApplicationDelegate.game = game
            #endif
        }
        .onDisappear {
            game.applicationActive = false
            game.chooseGameData = nil
            #if os(macOS)
            if OriginalApplicationDelegate.game === game { OriginalApplicationDelegate.game = nil }
            #endif
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            if game.canChooseGameData {
                Button("Game Data…", action: game.requestGameData)
                    .padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .fileImporter(isPresented: $game.showingLoadDialog, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                game.resume(from: url)
            } catch { game.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $game.showingExportDialog, document: game.exportDocument,
            contentType: game.exportIsJourney ? .json : .plainText, defaultFilename: game.exportFilename) { result in
                if case .success = result, let departure = game.exportDeparture { game.completeDeparture(departure) }
                if case .failure(let error) = result { game.error = error.localizedDescription }
                game.exportDeparture = nil
            }
        #endif
        .focusedSceneObject(game)
        #if os(macOS)
        .background(OriginalWindowActivation(changed: game.gameWindowActivationChanged))
        #endif
        .onChange(of: scenePhase) { phase in
            game.applicationActive = phase == .active
            if phase != .active { game.persist() }
        }
        .onChange(of: game.managementPane == nil) { closed in
            if closed { dismissManagementAlert() }
        }
    }

    private var gameSurface: some View {
        ZStack {
            ZStack {
            Group {
            if game.creatingGame && showingWelcome { OriginalTextDialogView(resource: 9220) { _ in showingWelcome = false } }
            else if game.creatingGame { OriginalRegistrationView(game: game) }
            else if let trip = game.trip {
                if trip.phase == .outfitting { OriginalOutfittingView(game: game, trip: trip) }
                else if trip.phase == .departure { OriginalTextDialogView(resource: 9080) { index in game.perform { try JourneyEngine.chooseDeparture(month: index + 3, in: &$0) } } }
                else if trip.phase == .finished { OriginalEndingView(game: game, trip: trip) }
                else if trip.phase == .hunting {
                    OriginalWindow {
                        OriginalHuntPane(input: huntInput(trip), random: game.random, audio: game.audio,
                            onCancel: { game.perform { try JourneyEngine.cancelHunt(&$0) } }) { result in
                            game.finishOriginalHunt(result)
                        }
                    }
                }
                else if trip.phase == .rafting {
                    OriginalWindow {
                        OriginalRaftPane(input: JourneyEngine.originalRaftInput(trip), random: game.random,
                            onLand: { result in game.perform { try JourneyEngine.prepareRaftLanding(result: result, in: &$0) } },
                            onSubmit: { result in game.perform { try JourneyEngine.applyRaftLosses(result: result, in: &$0) } },
                            onFinish: { _ in game.perform { try JourneyEngine.completeRaftLanding(in: &$0) } })
                    }
                }
                else { OriginalTrailView(game: game, trip: trip) }
            } else { titleScreen }
            }.allowsHitTesting((game.panel == nil || game.panel?.usesTrailPane == true) && game.error == nil)
                .accessibilityHidden((game.panel != nil && game.panel?.usesTrailPane != true) || game.error != nil)
            if let memorialID = game.memorialID {
                let hidden = (game.trip.map { [.hunting, .rafting, .finished].contains($0.phase) } ?? true) || game.panel == .shop
                OriginalDeathPane { game.memorialID = nil }.id(memorialID)
                    .originalPaneFrame(width: 262, height: 199)
                    .opacity(hidden ? 0 : 1).allowsHitTesting(!hidden).accessibilityHidden(hidden)
                    .frame(width: 512, height: 322, alignment: .topLeading).offset(x: OriginalWindowLayout.centerOrigin.x, y: OriginalWindowLayout.centerOrigin.y)
            }
            if let notice = game.actionNotice, game.trip?.phase != .finished {
                OriginalNoticePane(notice: notice, complete: game.dismissActionNotice).id(notice.id)
                    .originalPaneFrame(width: 262, height: 199)
                    .frame(width: 512, height: 322, alignment: .topLeading).offset(x: OriginalWindowLayout.centerOrigin.x, y: OriginalWindowLayout.centerOrigin.y)
            }
            if let panel = game.panel, !panel.usesTrailPane {
                if panel == .shop, let trip = game.trip {
                    OriginalWindow { OriginalStorePane(game: game, trip: trip) }
                } else {
                    PanelView(game: game, panel: panel).background(trailPaper)
                        .overlay(Rectangle().stroke(.black, lineWidth: 2)).padding(8)
                }
            }
            if let departure = game.pendingDeparture {
                OriginalExitGamePane(departure: departure, choose: game.answerDeparture)
                    .originalPaneFrame(width: 262, height: 119)
                    .frame(width: 512, height: 322, alignment: .topLeading).offset(x: OriginalWindowLayout.lowerCenterOrigin.x, y: OriginalWindowLayout.lowerCenterOrigin.y)
            }
            if game.showingSaveTimeOut {
                OriginalSaveTimeOutPane { game.showingSaveTimeOut = false }
                    .originalPaneFrame(width: 262, height: 199)
                    .frame(width: 512, height: 322, alignment: .topLeading).offset(x: OriginalWindowLayout.centerOrigin.x, y: OriginalWindowLayout.centerOrigin.y)
            }
            }.disabled(game.isOriginalModalPresented)
                .allowsHitTesting(!game.isOriginalModalPresented)
                .accessibilityHidden(game.isOriginalModalPresented)
            if game.showingIntroduction {
                originalModal(width: 492, height: 302) {
                    OriginalIntroductionPane { game.showingIntroduction = false }
                }
            }
            if game.showingAbout {
                originalModal(width: 400, height: 200) {
                    OriginalAboutPane(systemInformation: OriginalHostInformation.lines,
                        tickCount: { UInt32(truncatingIfNeeded: Int(ProcessInfo.processInfo.systemUptime * 60)) },
                        doubleClickTicks: originalDoubleClickTicks, done: { game.showingAbout = false })
                }
            }
            if let pane = game.managementPane {
                Group {
                    switch pane {
                    case .about:
                        originalModal(width: 488, height: 298) {
                            OriginalAboutManagementPane { game.managementPane = nil }
                        }
                    case .enableDisable:
                        originalModal(width: 312, height: 200, active: !managementAlertReady) {
                            OriginalEnableManagementPane(configuration: game.preferences,
                                enable: game.enableManagement, cancel: { game.managementPane = nil },
                                presentAlert: presentManagementAlert)
                        }
                    case .timeOptions:
                        originalModal(width: 210, height: 200) {
                            OriginalPreferencesPane(timing: game.preferences.timing,
                                save: game.saveTiming, cancel: { game.managementPane = nil })
                        }
                    case .changePassword:
                        originalModal(width: 312, height: 195, active: !managementAlertReady) {
                            OriginalChangePasswordPane(configuration: game.preferences,
                                save: game.savePreferences, cancel: { game.managementPane = nil },
                                presentAlert: presentManagementAlert)
                        }
                    case .clearLegends, .network: EmptyView()
                    }
                }.disabled(managementAlert != nil)
                    .allowsHitTesting(managementAlert == nil)
                    .accessibilityHidden(managementAlert != nil)
            }
            if game.showingLegendsManagement {
                if legendsConfirmationPresented {
                    Color.clear.contentShape(Rectangle()).onTapGesture {
                        #if os(macOS)
                        NSSound.beep()
                        #endif
                    }.accessibilityHidden(true)
                }
                originalModal(width: 300, height: 240, active: !legendsConfirmationPresented) {
                    OriginalClearLegendsPane(legends: game.legends,
                                             restoreOriginal: game.restoreOriginalLegends,
                                             done: game.finishLegendsManagement,
                                             onConfirmationChanged: { legendsConfirmationPresented = $0 })
                }
            }
            if let alert = managementAlert {
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    #if os(macOS)
                    NSSound.beep()
                    #endif
                }
                .accessibilityHidden(true)
                if managementAlertReady {
                    originalModal(width: 300, height: 125) {
                        OriginalManagementAlertContents(presentation: alert, dismiss: dismissManagementAlert)
                            .id(managementAlertID)
                    }
                }
                OriginalManagementAlertKeyboard(ready: managementAlertReady, dismiss: dismissManagementAlert)
                    .frame(width: 0, height: 0)
                    .disabled(game.error != nil)
            }
            if let error = game.error {
                Color.black.opacity(0.4)
                VStack(spacing: 15) {
                    Text(error).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button("OK") { game.error = nil }.keyboardShortcut(.defaultAction)
                }.padding(22).frame(width: 340).background(trailPaper).overlay(Rectangle().stroke(.black, lineWidth: 2))
            }
        }
    }

    /// Center the CONTENT with the original integer division. The System window
    /// frame extends outside it and must not move odd-height dialogs half a pixel.
    private func originalModal<Contents: View>(width: Int, height: Int, active: Bool = true,
                                               @ViewBuilder content: @escaping () -> Contents) -> some View {
        OriginalSystemModalFrame(contentWidth: width, contentHeight: height, active: active, content: content)
            .position(x: CGFloat((512 - width) / 2) + CGFloat(width) / 2,
                      y: CGFloat((322 - height) / 2) + CGFloat(height) / 2)
            .disabled(game.error != nil)
            .allowsHitTesting(game.error == nil)
            .accessibilityHidden(game.error != nil)
    }

    private func presentManagementAlert(_ purpose: OriginalManagementAlerts.Purpose) {
        guard managementAlert == nil else { return }
        let id = UUID()
        managementAlertID = id
        managementAlertReady = false
        managementAlert = OriginalManagementAlerts.presentation(purpose)
        GameAudio.shared.waitUntilIdle {
            guard managementAlertID == id, managementAlert != nil else { return }
            managementAlertReady = true
        }
    }

    private func dismissManagementAlert() {
        managementAlert = nil
        managementAlertReady = false
    }

    private var originalDoubleClickTicks: UInt32 {
        #if os(macOS)
        return UInt32(max(1, Int(NSEvent.doubleClickInterval * 60)))
        #else
        return 30
        #endif
    }

    private var titleScreen: some View {
        OriginalAttractView(game: game, travel: { showingWelcome = true; game.beginRegistration() })
    }

    private func huntInput(_ trip: Journey) -> OriginalHuntSession.Input {
        .init(destination: (TrailCatalog.stops.firstIndex { $0.id == (trip.destinationID ?? trip.locationID) } ?? 1) - 1,
              month: trip.month, weatherCategory: trip.originalWeatherCategory,
              snow: (trip.original?.weather.snow ?? 0) != 0, mileage: trip.miles,
              lastSuccessfulHuntMileage: trip.original?.lastSuccessfulHuntMileage ?? 0,
              ammunition: trip.inventory[.bullets], survivors: trip.livingMembers.count,
              currentFood: trip.huntingFood, foodCapacity: trip.huntingFoodCapacity,
              timeSetting: Int(trip.timing.huntSelector), originalDisplayFlag: true,
              edition: trip.gameEdition, rain: Int(trip.original?.weather.rain ?? 0))
    }
}
