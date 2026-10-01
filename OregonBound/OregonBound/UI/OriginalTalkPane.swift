import SwiftUI

/// DITL6080; classic CODE3:37c6 / CD CODE4:398a supply text and paired artwork.
/// No extra controls: another Talk sidebar click chooses the next authored quote.
struct OriginalTalkPane: View {
    let selection: OriginalTalkRules.Selection

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if let content = OriginalTalkRules.content(selection: selection,
                                                        strings: OriginalResources.strings(selection.resourceID)) {
                PixelArtwork(resource: content.portraitResourceID, monochromeResource: content.edition == .macintoshCD12 ? 6180 + content.portrait : 6080, frame: content.portraitFrame).frame(width: 154, height: 199)
                    .accessibilityHidden(true)
                PixelArtwork(resource: content.backgroundResourceID, monochromeResource: content.edition == .macintoshCD12 ? 6180 : 6080, frame: content.backgroundFrame).frame(width: 108, height: 199).offset(x: 154)
                    .accessibilityHidden(true)
                OriginalText(text: content.text, font: .plain12, width: 104)
                    .frame(width: 104, height: 170, alignment: .topLeading).clipped().offset(x: 146, y: 15)
            }
        }.frame(width: 262, height: 199).clipped()
    }
}
