import SwiftUI
import Combine

/// CODE18 animation/caption panes followed by CODE3:2220's result pane.
struct OriginalCrossingPane: View {
    let trip: Journey
    let outcome: OriginalRiverRules.Outcome
    let prepareResult: () -> Void
    let complete: () -> Void
    @State private var presentation: OriginalRiverResultPresentation?
    @State private var visible = false
    @State private var completed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime * 60) }
    private var method: OriginalRiverAnimation.Method {
        outcome.animationMethodRaw == 1 ? .ford : outcome.animationMethodRaw == 2 ? .caulk : .ferry
    }
    var body: some View {
        Group {
            if outcome.isPrepared {
                OriginalRiverResultPane(content: .init(outcome: outcome, names: trip.members.map(\.name))) {
                    // Event2 installs a zero-interval timer. It does not apply
                    // losses synchronously inside a button or keyboard callback.
                    presentation?.requestDismissal(active: visible && scenePhase == .active,
                                                   modalBlocked: modalBlocked)
                }
            } else {
                OriginalCrossingAnimationPane(method: method, outcome: outcome.failureKind == 0 ? .success : .failure) {
                    guard !outcome.isPrepared, !completed else { return }
                    prepareResult()
                }
            }
        }.frame(width: 262, height: 199)
            .onAppear { visible = true; beginPresentationIfNeeded(for: outcome) }
            // The captured view may have an old outcome. Use the value passed to this callback.
            .onChange(of: outcome) { updatedOutcome in beginPresentationIfNeeded(for: updatedOutcome) }
            .onDisappear {
                visible = false
                presentation?.advance(to: tick, active: false)
            }
            .onChange(of: scenePhase) { _ in presentation?.advance(to: tick, active: false) }
            .onReceive(timer) { _ in
                guard outcome.isPrepared, !completed else { return }
                if presentation?.advance(to: tick, active: visible && scenePhase == .active,
                                         modalBlocked: modalBlocked) == true {
                    completed = true
                    complete()
                }
            }
    }

    private func beginPresentationIfNeeded(for outcome: OriginalRiverRules.Outcome) {
        guard outcome.isPrepared, presentation == nil else { return }
        presentation = .init(isFailure: outcome.status == 1 || outcome.status == 2,
                             presentationRandomTicks: outcome.presentationRandomTicks,
                             observedTick: tick)
    }

}
