import SwiftUI
import Combine

/// DITL5300 and 5400, within the 262×199 area at the top center of the trail view.
/// Instantiate once per notification13; final-party UI instead queues the sound
/// while keeping its higher-priority loss page visible.
struct OriginalDeathPane: View {
    let complete: () -> Void
    @State private var presentation = OriginalDeathPresentation()
    @State private var visible = false
    @State private var started = false
    @State private var completed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0/60, on: .main, in: .common).autoconnect()
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime*60) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            PixelArtwork(resource: OriginalDeathPresentationRules.imageResource)
                .frame(width: 262, height: 155)
                .contentShape(Rectangle()).onTapGesture { finish() }
                .accessibilityLabel("Memorial").accessibilityAction { finish() }
            Rectangle().fill(.black).frame(width: 262, height: 1).offset(y: 156)
            OriginalText(text: OriginalDeathPresentationRules.caption, font: .bold14)
                .frame(width: 256, height: 17, alignment: .top)
                .offset(x: 3, y: CGFloat(OriginalDeathPresentationRules.captionTextTop))
        }.frame(width: 262, height: 199)
            .onAppear {
                visible = true
                if !modalBlocked { presentation.advance(to: tick, active: scenePhase == .active) }
                if !modalBlocked && !started { started = true; GameAudio.shared.enqueue(OriginalDeathPresentationRules.soundResource) }
            }
            .onDisappear { visible = false; presentation.advance(to: tick, active: false) }
            .onChange(of: scenePhase) { _ in presentation.advance(to: tick, active: false) }
            .onReceive(timer) { _ in
                guard !modalBlocked else { return }
                if !started { started = true; GameAudio.shared.enqueue(OriginalDeathPresentationRules.soundResource) }
                presentation.advance(to: tick, active: visible && scenePhase == .active)
                if presentation.isFinished { finish() }
            }
    }
    private func finish() {
        guard !completed, !modalBlocked else { return }
        presentation.dismiss()
        completed = true
        complete()
    }
}
