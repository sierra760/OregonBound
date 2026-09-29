import SwiftUI

/// Attach within a pane that installs default ordinal1/cancel ordinal0. Does not take focus,
/// modify selection, or install a global event monitor.
struct OriginalGameDefaultButtonKeyboard: View {
    let performDefault: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(macOS)
        GameDefaultButtonMonitor(enabled: isEnabled, performDefault: performDefault)
            .frame(width: 0, height: 0)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
import AppKit

/// This is also the production local-monitor delivery path exercised by tests.
/// Window facts are captured by the view, so tests need no foreground NSWindow.
@MainActor final class OriginalGameDefaultKeyDelivery {
    private(set) var didActivate = false

    func deliver(_ event: NSEvent, ownerWindowNumber: Int?, ownerIsKey: Bool,
                 enabled: Bool, performDefault: () -> Void) -> NSEvent? {
        guard enabled, ownerIsKey, let ownerWindowNumber,
              event.windowNumber == ownerWindowNumber else { return event }
        let kind: OriginalGameDefaultKeyRules.EventKind
        switch event.type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        default: return event
        }
        let bytes = event.characters?.data(using: .macOSRoman)
        let character = bytes?.count == 1 ? bytes?.first : nil
        switch OriginalGameDefaultKeyRules.action(
            kind: kind, character: character,
            command: event.modifierFlags.contains(.command), repeating: event.isARepeat) {
        case .passThrough: return event
        case .consume: return nil
        case .activate:
            // SwiftUI removes the overlay asynchronously. A second queued key
            // must not execute the same presentation's action again.
            guard !didActivate else { return nil }
            didActivate = true
            performDefault()
            return nil
        }
    }
}

private struct GameDefaultButtonMonitor: NSViewRepresentable {
    let enabled: Bool
    let performDefault: () -> Void
    func makeNSView(context: Context) -> GameDefaultButtonKeyboardView {
        GameDefaultButtonKeyboardView()
    }
    func updateNSView(_ view: GameDefaultButtonKeyboardView, context: Context) {
        view.enabled = enabled
        view.performDefault = performDefault
    }
    static func dismantleNSView(_ view: GameDefaultButtonKeyboardView, coordinator: ()) {
        view.stop()
    }
}

private final class GameDefaultButtonKeyboardView: NSView {
    var enabled = true
    var performDefault: () -> Void = {}
    private let delivery = OriginalGameDefaultKeyDelivery()
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.delivery.deliver(event, ownerWindowNumber: self.window?.windowNumber,
                                         ownerIsKey: self.window?.isKeyWindow == true,
                                         enabled: self.enabled, performDefault: self.performDefault)
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    deinit { stop() }
}
#endif
