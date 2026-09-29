import SwiftUI

/// Enabled CDEF0 Color QuickDraw appearance; retains the caller's native Button
/// activation, keyboard shortcuts, accessibility and full rectangular hit area.
struct OriginalSystemPushButtonStyle: ButtonStyle {
    let title: String
    var isDefault = false
    var paper: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        OriginalSystemPushButtonArtwork(title:title,isDefault:isDefault,paper:paper,pressed:configuration.isPressed)
    }
}

/// Separated artwork permits deterministic rendering tests for pressed state.
/// Parent supplies integer size through .frame, just as for OriginalButton.
struct OriginalSystemPushButtonArtwork: View {
    let title: String
    var isDefault = false
    var paper: Color = .white
    var pressed = false

    var body: some View {
        GeometryReader { geometry in
            let width = Int(geometry.size.width), height = Int(geometry.size.height)
            if width > 0 && height > 0 {
                ZStack(alignment:.topLeading) {
                    spans(OriginalSystemPushButtonRules.body(width:width,height:height),color:pressed ? .black : paper)
                    label(width:width,height:height)
                        .frame(width:CGFloat(width),height:CGFloat(height),alignment:.topLeading).clipped()
                    spans(OriginalSystemPushButtonRules.outline(width:width,height:height),color:.black)
                    if isDefault {
                        // Canvas itself includes the out-of-bounds ring. The
                        // hit region below remains the original control rect.
                        spans(OriginalSystemPushButtonRules.defaultRing(width:width,height:height),color:.black,translation:4)
                            .frame(width:CGFloat(width+8),height:CGFloat(height+8)).offset(x:-4,y:-4)
                    }
                }
                .frame(width:CGFloat(width),height:CGFloat(height),alignment:.topLeading)
                .contentShape(Rectangle())
            }
        }.accessibilityLabel(title)
    }

    private func spans(_ values:[OriginalSystemPushButtonRules.Span],color:Color,translation:Int=0) -> some View {
        Canvas { context, _ in
            for value in values {
                context.fill(Path(CGRect(x:value.x+translation,y:value.y+translation,width:value.width,height:1)),with:.color(color),style:FillStyle(antialiased:false))
            }
        }.allowsHitTesting(false)
    }

    @ViewBuilder private func label(width:Int,height:Int) -> some View {
        if let font = BitmapFont.chicago12 {
            let lines = title.components(separatedBy:"\r")
            let origins = OriginalSystemPushButtonRules.labelOrigins(width:width,height:height,lineWidths:lines.map(font.width))
            Canvas { context, _ in
                for (line,origin) in zip(lines,origins) {
                    for glyph in font.layout(line).glyphs {
                        let rect = glyph.rect.offsetBy(dx:CGFloat(origin.x),dy:CGFloat(origin.y))
                        var ink = context
                        // Mask the original alpha ink into the source label color.
                        // Frame/ring are separate and never inverted on press.
                        ink.clipToLayer { mask in
                            mask.draw(Image(decorative:glyph.image,scale:1).interpolation(.none),in:rect)
                        }
                        ink.fill(Path(rect),with:.color(pressed ? paper : .black),style:FillStyle(antialiased:false))
                    }
                }
            }.allowsHitTesting(false)
        } else {
            // Explicit missing-asset compatibility fallback, not original ink.
            Text(title).foregroundStyle(pressed ? paper : .black)
                .frame(width:CGFloat(width),height:CGFloat(height))
                .allowsHitTesting(false)
        }
    }
}
