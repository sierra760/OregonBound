#if os(macOS)
import SwiftUI
import AppKit

/// Only the game window supplies original activate events. App-level activation
/// is insufficient: Standard File and other windows can take keyboard focus.
struct OriginalWindowActivation: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(changed: changed) }
    func updateNSView(_ view: ObserverView, context: Context) { view.changed = changed }

    final class ObserverView: NSView {
        var changed: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }
            let center = NotificationCenter.default
            for (name, active) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.changed(active) }
                })
            }
            for (name, active) in [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)] {
                observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window,
                              (NSApp.keyWindow ?? NSApp.mainWindow) === window else { return }
                        self.changed(active)
                    }
                })
            }
            // Defer initial publication until SwiftUI has finished mounting.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.changed(window.isKeyWindow)
            }
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
#endif
