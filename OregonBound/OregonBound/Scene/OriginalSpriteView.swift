import SpriteKit
import SwiftUI

/// Explicitly applies the renderer's pause state when SwiftUI updates it. The
/// native SpriteView can leave its SKView paused after initial scene activation.
#if os(macOS)
struct OriginalSpriteView: NSViewRepresentable {
    let scene: SKScene
    var isPaused = false
    var preferredFramesPerSecond = 60

    func makeNSView(context: Context) -> Renderer { Renderer() }

    func updateNSView(_ view: Renderer, context: Context) {
        view.preferredFramesPerSecond = preferredFramesPerSecond
        if view.scene !== scene { view.presentScene(scene) }
        view.requestedPause = isPaused
        view.applyPause()
    }

    final class Renderer: SKView {
        var requestedPause = true
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { isPaused = true; return }
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyPause() }
                })
            }
            observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPause() }
            })
            applyPause()
        }

        func applyPause() {
            isPaused = requestedPause
            // AppKit may change SKView's pause state later in the mounting pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.isPaused = self.requestedPause
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
#else
struct OriginalSpriteView: View {
    let scene: SKScene
    var isPaused = false
    var preferredFramesPerSecond = 60
    var body: some View {
        SpriteView(scene: scene, isPaused: isPaused, preferredFramesPerSecond: preferredFramesPerSecond)
    }
}
#endif
