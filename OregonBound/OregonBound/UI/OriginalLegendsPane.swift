import SwiftUI

/// The 494×304 DITL9010 legends pane. Its parent provides OriginalWindow and controls
/// the title/legends attract timer; this page has no game-time or RNG effects.
struct OriginalLegendsPane: View {
    let legends: [OriginalEndingPresentation.Legend]
    let load: () -> Void
    let travel: () -> Void
    let advance: () -> Void
    private var rows: [OriginalLegendsRules.Row] { OriginalLegendsRules.rows(legends) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper.onTapGesture(perform: advance)
            Group {
            PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 0).frame(width: 135, height: 112)
            PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 1).frame(width: 213, height: 45).offset(x: 146, y: 26)
            PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 2).frame(width: 135, height: 112).offset(x: 359)
            PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 3).frame(width: 26, height: 26).offset(y: 278)
            PixelArtwork(resource: 19010, monochromeResource: 9010, frame: 4).frame(width: 26, height: 26).offset(x: 468, y: 278)
            if rows.isEmpty {
                OriginalText(text: OriginalLegendsRules.emptyMessage, font: .bold14)
                    .frame(width: 434, alignment: .center)
                    .offset(x: 30, y: CGFloat(OriginalLegendsRules.emptyMessageTop))
            } else {
                ForEach(rows) { row in
                    let y = CGFloat(OriginalLegendsRules.rowTop(row.id))
                    OriginalText(text: row.rank, font: .bold14).offset(x: 30, y: y)
                    OriginalText(text: row.name, font: .bold14).offset(x: 62, y: y)
                    OriginalText(text: row.classification, font: .bold14).offset(x: 314, y: y)
                    OriginalText(text: row.points, font: .bold14)
                        .frame(width: 464, alignment: .trailing).offset(y: y)
                }
            }
            }.allowsHitTesting(false)
            OriginalButton(title: "Load Game", action: load)
                .frame(width: 120, height: 20).offset(x: 30, y: 270)
            OriginalButton(title: "Travel the Trail", action: travel)
                .frame(width: 120, height: 20).offset(x: 343, y: 270)
        }.frame(width: 494, height: 304).clipped()
    }
}
