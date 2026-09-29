import SwiftUI
import Combine

/// DITL6340 / CODE6:0a2c. Original outcome panel is dismissed after600 ticks or OK.
struct OriginalHuntResultPane: View {
    let result: OriginalHuntSession.Result
    let complete: () -> Void
    @State private var countdown = OriginalDialogTimer(ticks: 600)
    @State private var visible = false
    @State private var completed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0/60, on: .main, in: .common).autoconnect()
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime*60) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text: "Outcome of Hunting:", font: .plain12)
                .frame(width: 142, height: 20, alignment: .topLeading).offset(x: 8, y: 4)
            OriginalText(text: result.message, font: .bold12, width: 240)
                .frame(width: 240, height: 131, alignment: .topLeading).clipped().offset(x: 8, y: 28)
            OriginalButton(title: "OK") { finish() }
                .frame(width: 60, height: 20).offset(x: 104, y: 168)
        }.frame(width: 262, height: 199)
            .onAppear { visible = true; if !modalBlocked { countdown.advance(to: tick, active: scenePhase == .active) } }
            .onDisappear { visible = false; countdown.advance(to: tick, active: false) }
            .onChange(of: scenePhase) { _ in countdown.advance(to: tick, active: false) }
            .onReceive(timer) { _ in
                guard !modalBlocked else { return }
                countdown.advance(to: tick, active: visible && !completed && scenePhase == .active)
                if countdown.isFinished { finish() }
            }
    }
    private func finish() {
        guard !completed, !modalBlocked else { return }
        completed = true
        complete()
    }
}
