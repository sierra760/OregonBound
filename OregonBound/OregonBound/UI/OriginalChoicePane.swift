import SwiftUI

/// The 262×199 trail-pane dialogs DITL 6030/6050 and their help/response pages.
struct OriginalChoicePane: View {
    @ObservedObject var game: GameController
    let trip: Journey
    let panel: GamePanel
    @State private var help = false
    @State private var alreadySelected = false
    private var isPace: Bool { panel == .pace }
    private var resource: Int { isPace ? 6050 : 6030 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
            originalPaper
            OriginalText(text: isPace ? "How fast do you want to travel?" : "How much do you want to eat?", width: 243)
                .offset(x: 11, y: 9)
            ForEach(0..<3) { index in
                OriginalIconChoice(icon: resource + index, title: title(index), width: 185) { choose(index) }
                    .offset(x: 13, y: CGFloat(44 + index * 51))
            }
            OriginalIconChoice(icon: 9999, title: "", width: 42) { help = true }
                .accessibilityLabel("Help").offset(x: 202, y: 95)
            }.allowsHitTesting(!help && !alreadySelected).accessibilityHidden(help || alreadySelected)
            if help {
                OriginalDialogContents(resource: isPace ? 6060 : 6040) { _ in help = false }
            }
            if alreadySelected {
                OriginalDialogContents(resource: resource + 1,
                                       substitutions: [isPace ? trip.pace.rawValue.lowercased() : trip.rations.rawValue.lowercased()]) { _ in
                    alreadySelected = false
                    game.panel = nil
                }
            }
        }
    }
    private func title(_ index: Int) -> String {
        isPace ? ["A steady pace", "A strenuous pace", "A grueling pace"][index] : ["Filling", "Meager", "Bare bones"][index]
    }
    private func choose(_ index: Int) {
        if (isPace ? Int(trip.pace.originalIndex) : Int(trip.rations.originalIndex)) == index {
            alreadySelected = true
        } else {
            game.perform {
                if isPace {
                    $0.pace = Pace.allCases[index]
                    $0.record(OriginalJournalRules.decision(.pace(index)))
                } else {
                    $0.rations = Rations.allCases[index]
                    $0.record(OriginalJournalRules.rations(index))
                }
            }
            game.panel = nil
        }
    }
}

struct OriginalIconChoice: View {
    let icon: Int
    let title: String
    let width: CGFloat
    let action: () -> Void
    var body: some View {
        if GameData.edition == .macintoshCD12 {
            Button(action: action) { Color.clear.frame(width: width, height: 46) }
                .buttonStyle(CDIconControlStyle(resource: icon, title: title, width: width))
                .accessibilityLabel(title)
        } else {
            Button(action: action) {
                HStack(spacing: 5) {
                    ZStack {
                        PixelArtwork(resource: 10129, monochromeResource: 129).frame(width: 42, height: 46)
                        PixelArtwork(resource: icon, type: OriginalResources.iconType).frame(width: 32, height: 32)
                    }
                    if !title.isEmpty { OriginalText(text: title) }
                }.frame(width: width, height: 46, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

private struct CDIconControlStyle: ButtonStyle {
    let resource: Int
    let title: String
    let width: CGFloat
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        CDIconControlArtwork(resource: resource, title: title, width: width,
                             pressed: configuration.isPressed, enabled: enabled).contentShape(Rectangle())
    }
}

/// CDEF10:0280–0374 and CODE1:28a6–2994 share the oval and icon geometry.
struct CDIconControlArtwork: View {
    let resource: Int
    var title = ""
    var width: CGFloat = 42
    var pressed = false
    var enabled = true
    var body: some View {
        ZStack(alignment: .topLeading) {
            PixelArtwork(resource: 10129, monochromeResource: 129, frame: pressed && enabled ? 1 : 0,
                         type: OriginalResources.imageType).frame(width: 42, height: 46)
            if enabled {
                PixelArtwork(resource: resource, type: OriginalResources.iconType)
                    .frame(width: 32, height: 32).offset(x: pressed ? 8 : 4, y: 7)
            }
            if !title.isEmpty, width > 47 {
                let textHeight = Int(BitmapFont.bold14?.layout(title).size.height ?? 18)
                // CDEF10:01b0–01e6 starts at the last baseline, so an odd
                // positive gap leaves the extra pixel above the text.
                let top = 46 - textHeight - (46 - textHeight) / 2
                OriginalText(text: title).offset(x: 47, y: CGFloat(top))
                if !enabled {
                    CDDisabledControlTextPattern().frame(width: width - 47, height: 46).offset(x: 47)
                }
            }
        }.frame(width: width, height: 46, alignment: .topLeading).clipped()
    }
}

/// CDEF10:0234–0256: AA55 patBic removes alternate label pixels at port phase.
struct CDDisabledControlTextPattern: View {
    var paper: Color = originalPaper
    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .named(OriginalWindowLayout.portSpace)).origin
            Canvas { context, size in
                let phase = (Int(origin.x) & 1) ^ (Int(origin.y) & 1)
                for y in 0..<max(0, Int(size.height)) {
                    for x in stride(from: (y & 1) ^ phase, to: max(0, Int(size.width)), by: 2) {
                        context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                                     with: .color(paper), style: FillStyle(antialiased: false))
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
