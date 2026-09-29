import SwiftUI

/// CODE3:2220, DITL6320/6330. The owner schedules the default action's idle pulse.
struct OriginalRiverResultPane: View {
    let content: OriginalRiverResultContent
    let requestDismissal: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if content.isFailure {
                OriginalTextBox(text: content.heading, font: .plain12, width: 242, height: 17)
                    .offset(x: 10, y: 8)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(content.lossRuns.enumerated()), id: \.offset) { _, run in
                        OriginalText(text: run.text, font: .plain12)
                            .offset(x: CGFloat(run.x - 10), y: CGFloat(run.y - 30))
                    }
                }.frame(width: 241, height: 130, alignment: .topLeading).clipped().offset(x: 10, y: 30)
            } else {
                OriginalTextBox(text: content.heading, width: 236, height: 64)
                    .offset(x: 12, y: 73)
            }
            OriginalButton(title: "OK", isDefault: true, action: requestDismissal)
                .frame(width: 60, height: 20).offset(x: 100, y: 168)
                #if !os(macOS)
                .keyboardShortcut(.defaultAction)
                #endif
            OriginalGameDefaultButtonKeyboard(performDefault: requestDismissal)
        }.frame(width: 262, height: 199, alignment: .topLeading)
            .originalPaneFrame(width: 262, height: 199)
    }
}

/// Separate source rect4/rect5 panes; the journal remains visible below them.
struct OriginalCrossingAnimationPane: View {
    let method: OriginalRiverAnimation.Method
    let outcome: OriginalRiverAnimation.Outcome
    let complete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            OriginalRiverArtwork(method: method, outcome: outcome, onComplete: complete)
                .frame(width: 262, height: 155).originalPaneFrame(width: 262, height: 155)
            OriginalTextBox(text: OriginalResources.strings(3021)[3], width: 256, height: 17, centered: true)
                .offset(x: 3, y: 12)
                .frame(width: 262, height: 41, alignment: .topLeading)
                .originalPaneFrame(width: 262, height: 41).offset(y: 158)
        }.frame(width: 262, height: 199, alignment: .topLeading)
    }
}
