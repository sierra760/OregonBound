import SwiftUI

/// Includes the original 8-pixel dBoxProc frame outside the content.
/// Uses recovered requested RGB; this does not emulate an indexed display CLUT.
struct OriginalSystemModalFrame<Content: View>: View {
    let contentWidth: Int
    let contentHeight: Int
    var active: Bool = true
    var monochrome = OriginalResources.colorMode == .monochrome
    var windowColors: [Int: OriginalSystemModalFrameRules.RGB16] = [:]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geometry in
                let origin = geometry.frame(in: .named(OriginalWindowLayout.portSpace)).origin
                let pattern = monochrome && !active ? TextureLoader.quickDrawGray(
                    width: contentWidth+16, height: contentHeight+16,
                    originX: Int(origin.x), originY: Int(origin.y)) : nil
                Canvas { context, _ in
                    for fill in OriginalSystemModalFrameRules.fills(contentWidth: contentWidth, contentHeight: contentHeight, active: active) {
                        let rect = CGRect(x: fill.x, y: fill.y, width: fill.width, height: fill.height)
                        if monochrome {
                            switch OriginalSystemModalFrameRules.monochromeInk(fill.colorIndex, active: active) {
                            case .black: context.fill(Path(rect), with: .color(.black), style: FillStyle(antialiased: false))
                            case .white: context.fill(Path(rect), with: .color(.white), style: FillStyle(antialiased: false))
                            case .gray:
                                if let pattern {
                                    var clipped = context
                                    clipped.clip(to: Path(rect), style: FillStyle(antialiased: false))
                                    clipped.draw(Image(decorative: pattern, scale: 1).interpolation(.none),
                                                 in: CGRect(x: 0, y: 0, width: contentWidth+16, height: contentHeight+16))
                                }
                            }
                        } else {
                            let rgb = OriginalSystemModalFrameRules.color(fill.colorIndex, windowColors: windowColors)
                            let color = Color(red: Double(rgb.red)/65535, green: Double(rgb.green)/65535, blue: Double(rgb.blue)/65535)
                            context.fill(Path(rect), with: .color(color), style: FillStyle(antialiased: false))
                        }
                    }
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
