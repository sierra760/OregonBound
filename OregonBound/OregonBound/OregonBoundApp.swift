import SwiftUI

@main
struct OregonBoundApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(OriginalApplicationDelegate.self) private var appDelegate
    #endif
    init() {
        if let status = GameDataCommandLine.runIfRequested() { exit(status) }
        _ = OriginalRandomStream.shared
    }

    var body: some Scene {
        #if os(macOS)
        Window("Oregon Bound", id: "game") {
            ContentView()
                .frame(minWidth: OriginalWindowGeometry.minimumSize.width, minHeight: OriginalWindowGeometry.minimumSize.height)
        }
        .defaultSize(width: 1024, height: 644)
        .commands { OriginalGameCommands() }
        #else
        WindowGroup {
            ContentView()
        }
        .commands { OriginalTabletMenus() }
        #endif
    }
}

struct OriginalGameCommands: Commands {
    @FocusedObject private var game: GameController?
    private var acceptsCommands: Bool { game != nil && game?.isOriginalModalPresented != true }
    private var acceptsGameMenus: Bool { game?.canUseGameMenus == true }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Load Game…") { game?.requestLoadGame() }.disabled(!acceptsCommands || game?.fileMenu.permits(.load) != true)
            Button("Save Game…") { game?.requestManualSave() }
                .keyboardShortcut("s").disabled(!acceptsCommands || game?.fileMenu.permits(.save) != true)
        }
        CommandGroup(after: .saveItem) {
            Button("Game Data…") { game?.requestGameData() }.disabled(game?.canChooseGameData != true)
            Button("Export Trail Log…") { game?.requestExportTrailLog() }.disabled(!acceptsCommands || game?.fileMenu.permits(.exportLog) != true)
            Button("Exit Game") { game?.requestDeparture(.exitGame) }.keyboardShortcut("e").disabled(!acceptsCommands || game?.fileMenu.permits(.exitGame) != true)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Oregon Bound…") {
                #if os(macOS)
                game?.presentAbout(alternate: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
                #else
                game?.presentAbout()
                #endif
            }.disabled(!acceptsCommands)
        }
        CommandGroup(replacing: .help) {
            if game?.store.edition == .macintoshCD12 {
                Button("On-line User’s Guide…") { game?.presentUserGuide() }
                    .disabled(game?.canPresentUserGuide != true)
            }
        }
        #if os(macOS)
        CommandGroup(replacing: .appTermination) {
            Button("Quit") {
                if let game { game.requestDeparture(.quit) } else { NSApp.terminate(nil) }
            }.keyboardShortcut("q")
                .disabled(game != nil && (!acceptsCommands || game?.fileMenu.permits(.quit) != true))
        }
        #endif
        CommandMenu("Game") {
            Button("Introduction…") { game?.requestIntroduction() }
                .keyboardShortcut("i").disabled(!acceptsGameMenus)
            Toggle("Sound On", isOn: Binding(get: { game?.sound ?? true }, set: { game?.setSoundFromMenu($0) })).disabled(!acceptsGameMenus)
        }
        CommandMenu("Management") {
            Button("About Management…") { game?.openManagement(.about) }.disabled(!acceptsGameMenus)
            Button(game?.management.enabled == true ? "Disable Management" : "Enable Management…") {
                game?.openManagement(.enableDisable)
            }.disabled(!acceptsGameMenus)
            Divider()
            Button("Clear List of Legends…") { game?.openManagement(.clearLegends) }
                .disabled(!acceptsGameMenus || game?.management.permits(.clearLegends) != true)
            Button("Time Options…") { game?.openManagement(.timeOptions) }
                .disabled(!acceptsGameMenus || game?.management.permits(.timeOptions) != true)
            Button("Change Password…") { game?.openManagement(.changePassword) }
                .disabled(!acceptsGameMenus || game?.management.permits(.changePassword) != true)
        }
    }
}
