import SwiftUI

/// Place at (8,130) in the 210×200 Time Options dialog, above the other controls.
/// Includes label and box; menu extends beyond these bounds and must not be clipped.
struct OriginalHuntTimePopup: View {
    @Binding var selection: Int
    var trackingChanged: (Bool) -> Void = { _ in }
    @State private var state = OriginalHuntTimePopupRules.State()
    @Environment(\.isEnabled) private var isEnabled
    private typealias Rules = OriginalHuntTimePopupRules

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if state.isTracking {
                Rectangle().fill(.black).frame(width:78,height:20)
            }
            OriginalText(text:Rules.label,font:.chicago12)
                .huntPopupInvertIf(state.isTracking).offset(x:5,y:3)
            Canvas { context, _ in
                func fill(_ x: Int,_ y: Int,_ width: Int,_ height: Int) {
                    context.fill(Path(CGRect(x:x,y:y,width:width,height:height)),with:.color(.black),style:FillStyle(antialiased:false))
                }
                // CODE15:1738 FrameRect,174a–176e one-pixel bottom/right shadow.
                fill(78,0,108,1); fill(78,19,108,1)
                fill(78,1,1,18); fill(185,1,1,18)
                fill(79,20,108,1); fill(186,1,1,19)
            }.frame(width:187,height:21).allowsHitTesting(false)
            OriginalText(text:Rules.titles[min(6,max(1,selection))-1],font:.chicago12)
                .offset(x:93,y:3).allowsHitTesting(false)
            Color.clear.frame(width:108,height:20).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("huntTimePopup"))
                    .onChanged { value in
                        let point = Rules.Point(x:Int(value.location.x.rounded(.down))+8,y:Int(value.location.y.rounded(.down))+130)
                        if !state.isTracking {
                            let start = Rules.Point(x:Int(value.startLocation.x.rounded(.down))+8,y:Int(value.startLocation.y.rounded(.down))+130)
                            state.press(at:start,selection:selection)
                            if state.isTracking { trackingChanged(true) }
                        }
                        state.drag(to:point)
                    }
                    .onEnded { value in
                        let wasTracking = state.isTracking
                        let point = Rules.Point(x:Int(value.location.x.rounded(.down))+8,y:Int(value.location.y.rounded(.down))+130)
                        if let newValue = state.release(at:point) { selection = newValue }
                        if wasTracking { trackingChanged(false) }
                    })
                .offset(x:78,y:0)
        }
        .frame(width:187,height:21,alignment:.topLeading)
        .overlay(alignment:.topLeading) { if state.isTracking { openMenu.allowsHitTesting(false) } }
        .coordinateSpace(name:"huntTimePopup")
        .onDisappear { if state.isTracking { state.cancel(); trackingChanged(false) } }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(Rules.label)
        .accessibilityValue(Rules.titles[min(6,max(1,selection))-1])
        // Native assistive input remains available without changing the
        // original held-button mouse menu into a modern sticky menu.
        .accessibilityAdjustableAction { direction in
            guard isEnabled, !state.isTracking else { return }
            switch direction {
            case .increment: selection = min(6, selection + 1)
            case .decrement: selection = max(1, selection - 1)
            @unknown default: break
            }
        }
    }
    private var openMenu: some View {
        let rect = Rules.menuRect(selection:state.originalSelection)
        return ZStack(alignment:.topLeading) {
            // MBDF0:09c2–0a1a: exterior frame/shadow, transparent corner gaps.
            Canvas { context, _ in
                func fill(_ x: Int,_ y: Int,_ width: Int,_ height: Int) {
                    context.fill(Path(CGRect(x:x+1,y:y+1,width:width,height:height)),with:.color(.black),style:FillStyle(antialiased:false))
                }
                fill(-1,-1,99,1); fill(-1,0,1,97)
                fill(97,0,1,97); fill(0,96,97,1)
                fill(2,96,97,2); fill(97,2,2,96)
            }.frame(width:100,height:99).offset(x:-1,y:-1)
            Rectangle().fill(.white).frame(width:97,height:96)
            ForEach(1...6,id:\.self) { item in
                let highlighted = state.highlightedItem == item
                ZStack(alignment:.topLeading) {
                    if highlighted { Rectangle().fill(.black) }
                    if item == state.originalSelection {
                        OriginalText(text:Rules.checkmark,font:.chicago12).huntPopupInvertIf(highlighted).offset(x:2,y:0)
                    }
                    OriginalText(text:Rules.titles[item-1],font:.chicago12).huntPopupInvertIf(highlighted).offset(x:14,y:0)
                }.frame(width:97,height:16,alignment:.topLeading).offset(y:CGFloat((item-1)*16))
            }
        }.frame(width:97,height:96,alignment:.topLeading)
            .offset(x:CGFloat(rect.x-8),y:CGFloat(rect.y-130))
    }
}

private extension View {
    @ViewBuilder func huntPopupInvertIf(_ condition: Bool) -> some View {
        if condition { self.colorInvert() } else { self }
    }
}
