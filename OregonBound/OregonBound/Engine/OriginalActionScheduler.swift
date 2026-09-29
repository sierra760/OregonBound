/// Original CODE16 action commands and timer/day-entry gates. Addresses exclude
/// CODE resource headers. See docs/ORIGINAL_ACTION_SCHEDULER.md.
enum OriginalActionScheduler {
    /// CONF1000+0x135 ->CODE8:1090 ->A5-296b ->CODE16:056c world+243.
    static let defaultTimerThreshold: UInt8 = 4
    enum Speed: UInt8 { case fast = 2, medium = 4, slow = 8 }
    static let timerIntervalTicks = 75 // CODE16:1daa, TickCount's 1/60 second ticks

    struct DayDecision: Equatable {
        var flags: UInt8
        var advancesDate: Bool
        var runsEvents: Bool
        var enteredResting: Bool
    }

    /// CODE16:1e0e–1e3c. Rest bypasses the travel-blocking bit16. Delay alone
    /// does not start a day; it requires moving or resting to remain scheduled.
    static func timerPermitsDay(flags: UInt8) -> Bool {
        flags & 4 != 0 || (flags & 2 != 0 && flags & 16 == 0)
    }

    /// CODE16:1df6–1e48. The callback resets its75-tick deadline each invocation.
    /// Paused callbacks retain the phase reached before crossing the threshold;
    /// Continue resets this byte separately at0db0.
    static func timerPulse(counter: inout UInt8, threshold: UInt8, flags: UInt8) -> Bool {
        guard flags != 0 else { return false } // CODE16:1dc6 inactive world
        counter &+= 1
        guard counter >= threshold else { return false }
        guard timerPermitsDay(flags: flags) else { counter &-= 1; return false }
        counter = 0
        return true
    }

    /// CODE16:1a9a–1aea after timer eligibility. No-oxen clears moving, but an
    /// already-entered mid-leg day still advances once. At remaining0, only rest
    /// permits date advancement. Event eligibility precedes counter processing.
    static func dayDecision(flags: UInt8, remainingMiles: Int, minimumRawOxen: Int) -> DayDecision {
        var result = DayDecision(flags: flags, advancesDate: false, runsEvents: false, enteredResting: flags & 4 != 0)
        guard timerPermitsDay(flags: flags) else { return result }
        if minimumRawOxen == 0 { result.flags &= ~2 }
        if remainingMiles == 0 {
            result.flags &= ~2
            guard result.flags & 4 != 0 else { return result }
        }
        result.advancesDate = true
        result.runsEvents = result.flags & 12 == 0
        return result
    }

    /// Rest command3 at0c74. Assign, do not add; preserve moving/delay flags.
    static func requestRest(days: UInt8, flags: inout UInt8, restDays: inout UInt8) {
        restDays = days
        flags |= 4
    }

    /// Time Out command4 at0cd2 and hunting command16 at0e3c.
    static func pauseTravel(flags: inout UInt8) { flags &= ~2 }

    /// Continue command5 at0daa. Neither Continue nor Time Out cancels rest.
    static func resumeTravel(flags: inout UInt8) { flags |= 2 }

    /// Last hunting wagon's completion, command6 at0e8a–0e96. Single-wagon mode
    /// always takes this path; no date/weather/health call is made by the command.
    static func finishHunt(flags: inout UInt8, restDays: inout UInt8) {
        restDays &+= 1
        flags |= 4
    }
}
