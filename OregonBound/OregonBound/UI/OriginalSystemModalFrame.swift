import SwiftUI

/// Includes the original 8-pixel dBoxProc frame outside the content.
/// Uses recovered requested RGB; this does not emulate an indexed display CLUT.
struct OriginalSystemModalFrame<Content: View>: View {
    let contentWidth: Int
    let contentHeight: Int
    var active: Bool = true
    var windowColors: [Int: OriginalSystemModalFrameRules.RGB16] = [:]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for fill in OriginalSystemModalFrameRules.fills(contentWidth: contentWidth, contentHeight: contentHeight, active: active) {
                    let rgb = OriginalSystemModalFrameRules.color(fill.colorIndex, windowColors: windowColors)
                    let color = Color(red: Double(rgb.red)/65535, green: Double(rgb.green)/65535, blue: Double(rgb.blue)/65535)
                    let rect = CGRect(x: fill.x, y: fill.y, width: fill.width, height: fill.height)
                    context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                }
            }
            .allowsHitTesting(false)
            content()
                .frame(width: CGFloat(contentWidth), height: CGFloat(contentHeight))
                .offset(x: 8, y: 8)
        }
        .frame(width: CGFloat(contentWidth+16), height: CGFloat(contentHeight+16))
    }
}
