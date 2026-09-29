import SwiftUI

/// QuickDraw PenPat(qd.gray) + FrameRect with its normal one-pixel pen.
/// The authored group origins have even pattern phase in their drawing ports.
struct OriginalSystemGroupFrame: View {
    let width: Int
    let height: Int
    var body: some View {
        Canvas { context, _ in
            guard width > 0, height > 0 else { return }
            func dot(_ x: Int, _ y: Int) {
                guard (x + y).isMultiple(of: 2) else { return }
                context.fill(Path(CGRect(x:x,y:y,width:1,height:1)),
                             with:.color(.black),style:FillStyle(antialiased:false))
            }
            for y in 0..<height {
                if y == 0 || y == height - 1 {
                    for x in 0..<width { dot(x,y) }
                } else {
                    dot(0,y)
                    dot(width-1,y)
                }
            }
        }.frame(width:CGFloat(width),height:CGFloat(height)).allowsHitTesting(false)
    }
}
