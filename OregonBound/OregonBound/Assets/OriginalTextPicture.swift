import SwiftUI

/// Text-only PICT resources retain QuickDraw text origins, baselines and faces.
/// Drawing the original NFNT strikes avoids modern PICT converters' missing fonts.
struct OriginalTextPicture: View {
    let resource: Int
    private struct Picture: Decodable {
        struct Run: Decodable {
            let x: Int
            let baseline: Int
            let font: Int
            let face: Int
            let size: Int
            let text: String
        }
        let width: Int
        let height: Int
        let runs: [Run]
    }
    private var picture: Picture? {
        guard let url = GameData.url(forResource: "pict_\(resource)", withExtension: "json", subdirectory: "pictures"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Picture.self, from: data)
    }
    private func font(_ run: Picture.Run) -> BitmapFont? {
        if run.size == 12 { return run.face & 1 == 0 ? .plain12 : .bold12 }
        return run.face & 1 == 0 ? .plain14 : .bold14
    }
    var body: some View {
        if let picture {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(picture.runs.enumerated()), id: \.offset) { _, run in
                    let strike = font(run)
                    OriginalText(text: run.text, font: strike)
                        .offset(x: CGFloat(run.x), y: CGFloat(run.baseline - (strike?.metrics.header.ascent ?? 0)))
                }
            // QuickDraw DrawPicture does not clip to the picture's header bounds.
            // PICT2051 deliberately draws its final line beyond that rectangle.
            }.frame(width: CGFloat(picture.width), height: CGFloat(picture.height))
        }
    }
}
