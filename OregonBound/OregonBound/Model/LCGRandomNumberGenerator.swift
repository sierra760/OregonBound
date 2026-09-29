import Foundation

/// Approximate random generator used by the legacy simulation.
/// The playable journey uses OriginalRandom.
///
/// The original game dispatches random calls through an A5-relative jump table:
///   - A5+0xa2 → primary RNG returning 0..<n  (use `rng(_:)`)
///   - A5+0x262 → unbounded raw state          (use `coinFlip()`)
///   - A5+0x272 → boolean bit check            (use `booleanCheck()`)
///
/// These constants are assumptions from the initial implementation and have
/// not been verified against the original generator.
struct LCGRandomNumberGenerator: RandomNumberGenerator {

    // MARK: - LCG Constants

    /// LCG multiplier (0x41C64E6D).
    static let multiplier: UInt32 = 1_103_515_245

    /// Increment 0x3039.
    static let increment: UInt32 = 12_345

    /// Restricts the generated state to 31 bits.
    static let mask: UInt32 = 0x7FFF_FFFF

    // MARK: - State

    var state: UInt32

    init(seed: UInt32 = 0) {
        self.state = seed
    }

    // MARK: - RandomNumberGenerator

    mutating func next() -> UInt64 {
        advance()
        return UInt64(state)
    }

    // MARK: - Original 68k API

    /// Returns a value in 0..<n, matching the A5+0xa2 primary_rng dispatch pattern.
    mutating func rng(_ n: Int) -> Int {
        advance()
        return Int(state % UInt32(n))
    }

    /// Returns the raw state value after one step, matching A5+0x262 (unbounded / coin-flip).
    mutating func coinFlip() -> Int {
        advance()
        return Int(state)
    }

    /// Returns bit 0 of the state after one step, matching A5+0x272 (boolean random check).
    mutating func booleanCheck() -> Bool {
        advance()
        return state & 1 == 1
    }

    // MARK: - Private

    private mutating func advance() {
        // Use UInt64 to hold the intermediate product safely (state < 2^31, multiplier < 2^31).
        let next = UInt64(state) * UInt64(LCGRandomNumberGenerator.multiplier)
                 + UInt64(LCGRandomNumberGenerator.increment)
        state = UInt32(next & UInt64(LCGRandomNumberGenerator.mask))
    }
}
