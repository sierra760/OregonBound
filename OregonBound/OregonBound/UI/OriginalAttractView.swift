import SwiftUI
import Combine

/// CODE4 title ↔ List of Legends cycle, including background-click advance.
struct OriginalAttractView: View {
    @ObservedObject var game: GameController
    let travel: () -> Void
    @State private var page = OriginalLegendsRules.AttractPage.title
    @State private var timing = OriginalDialogTimer(ticks: 7200)
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime * 60) }

    var body: some View {
        Group {
            if page == .title {
                OriginalTitleView(load: { game.requestLoadGame(fromAttractButton: true) }, travel: travel, advance: advance)
            } else {
                OriginalWindow {
                    OriginalLegendsPane(legends: game.legends,
                                        load: { game.requestLoadGame(fromAttractButton: true) }, travel: travel, advance: advance)
                }
            }
        }.onAppear { game.refreshOriginalLegends(); timing.advance(to: tick, active: true) }
            .onChange(of: scenePhase) { _ in timing.advance(to: tick, active: false) }
            .onReceive(timer) { _ in
                guard !game.isOriginalModalPresented else { return }
                timing.advance(to: tick, active: scenePhase == .active)
                if timing.isFinished { advance() }
            }
    }
    private func advance() {
        page = page.next
        timing.restart(ticks: page.durationTicks)
        if page == .legends { game.refreshOriginalLegends() }
    }
}
