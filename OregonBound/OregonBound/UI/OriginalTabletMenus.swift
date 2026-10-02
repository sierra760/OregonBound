import SwiftUI

#if os(iOS)
/// iPadOS 26 provides the system menu bar. The separate native help bar also
/// exposes Deluxe ancillary content on earlier supported iPadOS versions.
struct OriginalTabletMenus: Commands {
    var body: some Commands {
        if #available(iOS 26.0, *) {
            OriginalGameCommands()
        }
    }
}
#endif

/// Native document/help controls outside the original 512×322 game canvas.
/// Shared with the macOS target for offscreen verification; installed on iPad.
struct OriginalTabletHelpBar: View {
    @ObservedObject var game: GameController
    var body: some View {
        if game.canChooseGameData || game.store.edition == .macintoshCD12 {
            HStack {
                if game.canChooseGameData { Button("Game Data…", action: game.requestGameData) }
                if game.store.edition == .macintoshCD12 {
                    Menu {
                        Button("On-line User’s Guide…", action: game.presentUserGuide)
                            .disabled(!game.canPresentUserGuide)
                        Divider()
                        Button("About Oregon Bound…") { game.presentAbout() }
                        Button("About with alternate music…") { game.presentAbout(alternate: true) }
                    } label: {
                        Text("Help").frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!game.applicationActive || game.isOriginalModalPresented)
                }
            }.padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
}
