/// CODE3:2220 result-pane timer. Emits a closure request; it never applies losses,
/// advances the journey, draws randomness, or waits for audio.
struct OriginalRiverResultPresentation {
    enum Phase: Equatable { case initial, remaining, finished }
    private(set) var phase: Phase = .initial
    let initialTicks: Int
    let usedLegacyFallback: Bool
    private var interval: Int
    private var count = 0
    private var lastObservedTick: Int?
    var ticksRemaining: Int { max(0, interval - count) }
    var isFinished: Bool { phase == .finished }

    /// Use the saved CODE3:2296 draw for failures, 3 for safe results. JourneyStore
    /// accepts nil in legacy outcomes; initial3 preserves nominal180 without RNG.
    /// observedTick may be the shared timer observation anchor. If unavailable,
    /// pass the current tick on appearance, or nil to anchor the first active idle.
    init(isFailure: Bool, presentationRandomTicks: Int?, observedTick: Int? = nil) {
        if isFailure, let ticks = presentationRandomTicks {
            precondition((0..<180).contains(ticks), "Validated original result draw must be 0..<180")
            initialTicks = ticks
        } else {
            initialTicks = 3
        }
        usedLegacyFallback = isFailure && presentationRandomTicks == nil
        interval = initialTicks
        lastObservedTick = observedTick
    }

    /// Advances the timer once. A blocking modal preserves the last observed tick;
    /// app inactivity clears it, as in OriginalDialogTimer.
    /// Returns true when the result pane should close.
    @discardableResult
    mutating func advance(to tick: Int, active: Bool = true, modalBlocked: Bool = false) -> Bool {
        guard !isFinished else { return false }
        guard active else { lastObservedTick = nil; return false }
        guard !modalBlocked else { return false }
        let advanced: Bool
        if let previous = lastObservedTick {
            advanced = tick > previous
            if advanced { lastObservedTick = tick }
        } else {
            lastObservedTick = tick
            advanced = false
        }
        return idle(tickAdvanced: advanced)
    }

    /// Direct source-level entry when the caller already owns CODE5's shared
    /// TickCount observation. Call only on active, nonmodal dispatch passes.
    @discardableResult
    mutating func idle(tickAdvanced: Bool) -> Bool {
        guard !isFinished, tickAdvanced || interval == 0 else { return false }
        // CODE5:229e–22a6: increment once; fire when count >= interval.
        count += 1
        guard count >= interval else { return false }
        count = 0
        switch phase {
        case .initial:
            // CODE3:2380–239a. A replacement cannot fire again in this pass.
            interval = 180 - initialTicks
            phase = .remaining
            return false
        case .remaining:
            phase = .finished
            interval = 0
            return true
        case .finished:
            return false
        }
    }

    /// CODE3:2366–23ac: replace either phase with interval0 and the nonzero
    /// remaining sentinel. Completion occurs on the next eligible idle, even if
    /// TickCount is unchanged. Repeated OK before that idle only replaces again.
    mutating func requestDismissal(active: Bool = true, modalBlocked: Bool = false) {
        guard active, !modalBlocked, !isFinished else { return }
        phase = .remaining
        interval = 0
        count = 0
    }
}
