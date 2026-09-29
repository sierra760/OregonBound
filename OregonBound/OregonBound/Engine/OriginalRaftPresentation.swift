/// CODE17 intro30; CODE6 onshore period60 fires twice, with CODE5 observed-tick timing.
struct OriginalRaftPresentation {
    enum Phase: Equatable { case preparation, rafting, onshore, complete }
    enum Event: Equatable { case beginRafting, submitLosses, complete }
    private(set) var phase: Phase = .preparation
    private(set) var lossesSubmitted = false
    private var timer = OriginalDialogTimer(ticks: 30)
    private var hasSurvivors = true

    mutating func raftingFinished(survivors: Int) {
        guard phase == .rafting else { return }
        hasSurvivors = survivors > 0
        phase = .onshore
        timer.restart(ticks: hasSurvivors ? 60 : 0)
    }
    mutating func advance(to tick: Int,active: Bool) -> Event? {
        guard phase == .preparation || phase == .onshore else { return nil }
        timer.advance(to: tick,active: active)
        guard active, timer.isFinished else { return nil }
        if phase == .preparation { phase = .rafting; return .beginRafting }
        if hasSurvivors && !lossesSubmitted {
            lossesSubmitted = true; timer.restart(ticks: 60); return .submitLosses
        }
        phase = .complete; return .complete
    }
}
