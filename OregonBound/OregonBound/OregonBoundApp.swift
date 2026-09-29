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
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: OriginalWindowGeometry.minimumSize.width, minHeight: OriginalWindowGeometry.minimumSize.height)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1024, height: 644)
        .commands { OriginalGameCommands() }
        #elseif os(iOS)
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
            Button("Export Trail Log…") { game?.requestExportTrailLog() }.disabled(!acceptsCommands || game?.fileMenu.permits(.exportLog) != true)
            Button("Exit Game") { game?.requestDeparture(.exitGame) }.keyboardShortcut("e").disabled(!acceptsCommands || game?.fileMenu.permits(.exitGame) != true)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Oregon Bound…") { game?.showingAbout = true }.disabled(!acceptsCommands)
        }
        #if os(macOS)
        CommandGroup(replacing: .appTermination) {
            Button("Quit") { game?.requestDeparture(.quit) }.keyboardShortcut("q")
                .disabled(!acceptsCommands || game?.fileMenu.permits(.quit) != true)
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
