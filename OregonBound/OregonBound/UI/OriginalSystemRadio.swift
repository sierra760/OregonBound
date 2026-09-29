import SwiftUI

/// Radio control using the original bounds, Chicago 12 glyphs and QuickDraw ovals.
/// It keeps its enabled appearance while another modal control blocks input.
struct OriginalSystemRadio: View {
    let title: String
    let selected: Bool
    var interactionEnabled = true
    var width: Int = 75
    var height: Int = 15
    var paper: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(RadioStyle(title:title,selected:selected,width:width,height:height,paper:paper))
            .disabled(!interactionEnabled)
            .accessibilityLabel(title)
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private struct RadioStyle: ButtonStyle {
        let title: String
        let selected: Bool
        let width: Int
        let height: Int
        let paper: Color
        func makeBody(configuration: Configuration) -> some View {
            ZStack(alignment: .topLeading) {
                // CDEF0 erases radios with the owner window content color:
                // white in Time Options, yellow in the main game window.
                paper
                Canvas { context, _ in
                    let state = OriginalSystemRadioRules.State(selected:selected,highlight:configuration.isPressed ? 11 : 0)
                    for span in OriginalSystemRadioRules.markerSpans(state:state,control:.init(x:0,y:0,width:width,height:height)) {
                        context.fill(Path(CGRect(x:span.x,y:span.y,width:span.width,height:1)),with:.color(.black),style:FillStyle(antialiased:false))
                    }
                }.allowsHitTesting(false)
                OriginalText(text:title,font:.chicago12)
                    .fixedSize().offset(x:18,y:CGFloat(OriginalSystemRadioRules.labelBaseline(controlHeight:height)-12))
                    .allowsHitTesting(false)
            }
            .frame(width:CGFloat(width),height:CGFloat(height),alignment:.topLeading).clipped()
            // CDEF0:03fc–0418 PtInRect covers the entire control, not its oval.
            .contentShape(Rectangle())
        }
    }
}
