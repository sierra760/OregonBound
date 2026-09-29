import SwiftUI

/// DITL6080; CODE3:37c6 supplies plain12 quote text and two Imag16080 frames.
/// No extra controls: another Talk sidebar click chooses the next authored quote.
struct OriginalTalkPane: View {
    let selection: OriginalTalkRules.Selection

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if let content = OriginalTalkRules.content(selection: selection,
                                                        strings: OriginalResources.strings(selection.resourceID)) {
                PixelArtwork(resource: 16080, frame: content.portrait).frame(width: 154, height: 199)
                    .accessibilityHidden(true)
                PixelArtwork(resource: 16080, frame: 9).frame(width: 108, height: 199).offset(x: 154)
                    .accessibilityHidden(true)
                OriginalText(text: content.text, font: .plain12, width: 104)
                    .frame(width: 104, height: 170, alignment: .topLeading).clipped().offset(x: 146, y: 15)
            }
        }.frame(width: 262, height: 199).clipped()
    }
}
