#if os(macOS)
import SwiftUI
import AppKit

/// Locks the game window to the original 512x322 content proportions so the
/// artwork always fills the window; the title bar is excluded from the ratio.
struct OriginalWindowGeometry: NSViewRepresentable {
    let canvas: CGSize
    static let minimumSize = CGSize(width: 512, height: 322)

    func makeNSView(context: Context) -> GeometryView { GeometryView(canvas: canvas) }
    func updateNSView(_ view: GeometryView, context: Context) { view.canvas = canvas; view.apply() }

    final class GeometryView: NSView {
        var canvas: CGSize
        private var configuredWindow: NSWindow?

        init(canvas: CGSize) {
            self.canvas = canvas
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // SwiftUI restores the saved frame after attaching the view; conform that too.
            DispatchQueue.main.async { [weak self] in self?.conform() }
        }

        func apply() {
            guard let window, window !== configuredWindow || window.contentAspectRatio != canvas else { return }
            configuredWindow = window
            // SwiftUI's full-size content view would put the title bar inside the ratio.
            window.styleMask.remove(.fullSizeContentView)
            window.contentMinSize = OriginalWindowGeometry.minimumSize
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            // Setting resize increments clears the aspect constraint; set it last.
            window.contentAspectRatio = canvas
            conform()
        }

        private func conform() {
            guard let window, !window.styleMask.contains(.fullScreen), !window.inLiveResize else { return }
            // Conform a restored or default frame to the ratio, keeping its width.
            let content = window.contentRect(forFrameRect: window.frame)
            let width = max(OriginalWindowGeometry.minimumSize.width, content.width.rounded())
            let height = (width * canvas.height / canvas.width).rounded()
            guard abs(content.height - height) >= 1 || content.width != width else { return }
            var frame = window.frameRect(forContentRect: CGRect(x: content.minX, y: content.maxY - height, width: width, height: height))
            if let screen = window.screen?.visibleFrame, frame.height > screen.height || frame.width > screen.width {
                let fitWidth = min(screen.width, (screen.height - (frame.height - height)) * canvas.width / canvas.height).rounded(.down)
                let fitHeight = (fitWidth * canvas.height / canvas.width).rounded(.down)
                frame = window.frameRect(forContentRect: CGRect(x: content.minX, y: content.maxY - fitHeight, width: fitWidth, height: fitHeight))
            }
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
#endif
