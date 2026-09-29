/// QuickDraw Random plus the game's CODE 1:0x073e bounded wrapper.
/// See docs/ORIGINAL_RANDOM.md for the original source and edge cases.
struct OriginalRandom: Sendable {
    var seed: UInt32

    mutating func next() -> Int {
        seed = UInt32(UInt64(seed) * 16_807 % 2_147_483_647)
        let result = Int(Int16(truncatingIfNeeded: seed))
        return result == -32_768 ? 0 : result
    }

    mutating func bounded(_ bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        let value = next()
        if bound == 2 { return value & 1 }
        return abs(value) % bound
    }
}
