import SwiftUI
import Combine

struct OriginalActionNotice: Identifiable {
    let id = UUID()
    let text: String
    var ticks: Int? = nil
}

/// CODE6 rejection callbacks use DITL6320. Its template adds the terminal period.
struct OriginalNoticePane: View {
    let notice: OriginalActionNotice
    let complete: () -> Void
    @State private var countdown: OriginalDialogTimer
    @State private var visible = false
    @State private var completed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime * 60) }

    init(notice: OriginalActionNotice, complete: @escaping () -> Void) {
        self.notice = notice; self.complete = complete
        _countdown = State(initialValue: OriginalDialogTimer(ticks: notice.ticks ?? 0))
    }
    var body: some View {
        OriginalDialogContents(resource: 6320, substitutions: [notice.text]) { _ in finish() }
            .frame(width: 262, height: 199)
            .onAppear { visible = true; if !modalBlocked { countdown.advance(to: tick, active: scenePhase == .active) } }
            .onDisappear { visible = false; countdown.advance(to: tick, active: false) }
            .onChange(of: scenePhase) { _ in countdown.advance(to: tick, active: false) }
            .onReceive(timer) { _ in
                guard !modalBlocked else { return }
                guard notice.ticks != nil else { return }
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
