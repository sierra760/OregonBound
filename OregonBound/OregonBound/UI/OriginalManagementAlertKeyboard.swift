import SwiftUI

/// A nested NIL-filter ModalDialog owns keyboard events until OK. In particular,
/// Command-period must not reach the enclosing Management dialog's Cancel button.
struct OriginalManagementAlertKeyboard: View {
    let ready: Bool
    let dismiss: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        #if os(macOS)
        KeyboardMonitor(ready: ready, enabled: isEnabled, dismiss: dismiss)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
import AppKit

private struct KeyboardMonitor: NSViewRepresentable {
    let ready: Bool
    let enabled: Bool
    let dismiss: () -> Void
    func makeNSView(context: Context) -> AlertKeyboardView { AlertKeyboardView() }
    func updateNSView(_ view: AlertKeyboardView, context: Context) {
        view.ready = ready
        view.enabled = enabled
        view.dismiss = dismiss
    }
    static func dismantleNSView(_ view: AlertKeyboardView, coordinator: ()) { view.stop() }
}

private final class AlertKeyboardView: NSView {
    var ready = false
    var enabled = true
    var dismiss: () -> Void = {}
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.enabled, let window = self.window, event.window === window else { return event }
            if self.ready, event.type == .keyDown,
               let byte = event.characters?.data(using: .macOSRoman)?.first,
               OriginalManagementAlerts.response(to: .key(macRoman: byte, command: event.modifierFlags.contains(.command))) == .dismiss(item: 1) {
                self.dismiss()
            }
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    deinit { stop() }
}
#endif
