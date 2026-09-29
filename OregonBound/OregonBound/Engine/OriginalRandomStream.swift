import Foundation

/// One app-session QuickDraw randSeed, shared by UI, simulation, and minigames.
/// CODE9:0158–0160 reads Time($20c) once, then stores A5−200.
@MainActor final class OriginalRandomStream {
    static let shared = OriginalRandomStream()
    private var generator: OriginalRandom
    var seed: UInt32 {
        get { generator.seed }
        set { generator.seed = newValue }
    }
    init(seed: UInt32) { generator = OriginalRandom(seed: seed) }
    convenience init(date: Date = Date(), timeZone: TimeZone = .current) {
        self.init(seed: Self.clockSeed(date: date,timeZone: timeZone))
    }
    func next() -> Int { generator.next() }
    func bounded(_ bound: Int) -> Int { generator.bounded(bound) }

    /// Classic Time is local wall-clock seconds since1904, wrapping to32 bits.
    /// Explicit zone/date injection makes tests independent of the host clock.
    nonisolated static func clockSeed(date: Date,timeZone: TimeZone) -> UInt32 {
        let seconds = Int64(floor(date.timeIntervalSince1970)) + 2_082_844_800
                    + Int64(timeZone.secondsFromGMT(for: date))
        return UInt32(truncatingIfNeeded: seconds)
    }
}
