import SwiftUI

/// Classic ModalDialog/Standard File loops do not run the game's main idle
/// dispatcher. TickCount still advances: callers skip dispatch without rebasing
/// absolute deadlines or clearing observed-tick timer anchors.
private struct OriginalModalDispatchBlockedKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var originalModalDispatchBlocked: Bool {
        get { self[OriginalModalDispatchBlockedKey.self] }
        set { self[OriginalModalDispatchBlockedKey.self] = newValue }
    }
}
