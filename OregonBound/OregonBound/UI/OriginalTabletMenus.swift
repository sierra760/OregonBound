#if os(iOS)
import SwiftUI

/// iPadOS 26 provides the system menu bar. Earlier iPadOS versions receive no
/// custom menus or substitute controls inside the game canvas.
struct OriginalTabletMenus: Commands {
    var body: some Commands {
        if #available(iOS 26.0, *) {
            OriginalGameCommands()
        }
    }
}
#endif
