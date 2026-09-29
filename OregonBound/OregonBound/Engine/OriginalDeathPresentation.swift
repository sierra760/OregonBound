import Foundation

/// CODE5:223e–22ce. Each idle pass observes TickCount; a positive change counts
/// once, however many ticks elapsed. Native inactive views suspend observation.
struct OriginalDialogTimer {
    private(set) var remainingTicks: Int
    private var lastTick: Int?
    var isFinished: Bool { remainingTicks == 0 }
    init(ticks: Int) { remainingTicks = max(0, ticks) }
    mutating func advance(to tick: Int, active: Bool) {
        guard active else { lastTick = nil; return }
        defer { lastTick = tick }
        guard !isFinished, let lastTick, tick > lastTick else { return }
        remainingTicks -= 1
    }
    /// Timer replacement during the same idle pass keeps the observation anchor.
    mutating func restart(ticks: Int) { remainingTicks = max(0, ticks) }
}

/// CODE3:0cd0 and0c58; no random draws, calendar changes or movement restart.
struct OriginalDeathPresentation {
    enum Phase: Equatable { case initial, mourning, dismissed }
    private(set) var phase: Phase = .initial
    private var timer = OriginalDialogTimer(ticks: 60)
    var remainingTicks: Int { timer.remainingTicks }
    var isFinished: Bool { phase == .dismissed }
    mutating func advance(to tick: Int, active: Bool) {
        guard !isFinished else { return }
        timer.advance(to: tick, active: active)
        guard timer.isFinished else { return }
        if phase == .initial {
            phase = .mourning
            timer.restart(ticks: 540)
        } else { dismiss() }
    }
    mutating func dismiss() { phase = .dismissed }
}

enum OriginalDeathPresentationRules {
    enum MemorialPlacement: Equatable {
        case visible
        case behindPartyLoss
        case deferredUntilCrossingCleanup
    }
    /// Notification13 at CODE16:0500. Notification9 independently creates the
    /// priority3 loss page; priority1 memorial still initializes beneath it.
    static func memorialPlacement(survivors: Int, crossingResultActive: Bool) -> MemorialPlacement {
        if crossingResultActive { return .deferredUntilCrossingCleanup }
        return survivors == 0 ? .behindPartyLoss : .visible
    }
    static let imageResource = 19150
    static let soundResource = 9001
    static let caption = "Burying and mourning the dead…"
    // A5−2d5c rect4=(9,64,164,326), rect5=(167,64,208,326).
    static let captionTop = 158
    static let captionTextTop = 170
}
