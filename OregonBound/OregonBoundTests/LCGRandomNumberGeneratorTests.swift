import XCTest
@testable import OregonBound

final class LCGRandomNumberGeneratorTests: XCTestCase {

    // Reference vector: first 20 rng(1000) values from seed 0.
    // Derivation: state = (state * 1_103_515_245 + 12_345) & 0x7FFF_FFFF; result = state % 1000
    //   step  1: state =       12345, result = 345
    //   step  2: state =  1406932606, result = 606
    //   step  3: state =   654583775, result = 775
    //   step  4: state =  1449466924, result = 924
    //   step  5: state =   229283573, result = 573
    //   step  6: state =  1109335178, result = 178
    //   step  7: state =  1051550459, result = 459
    //   step  8: state =  1293799192, result = 192
    //   step  9: state =   794471793, result = 793
    //   step 10: state =   551188310, result = 310
    //   step 11: state =   803550167, result = 167
    //   step 12: state =  1772930244, result = 244
    //   step 13: state =   370913197, result = 197
    //   step 14: state =   639546082, result =  82
    //   step 15: state =  1381971571, result = 571
    //   step 16: state =  1695770928, result = 928
    //   step 17: state =  2121308585, result = 585
    //   step 18: state =  1719212846, result = 846
    //   step 19: state =   996984527, result = 527
    //   step 20: state =  1157490780, result = 780
    private let referenceVector: [Int] = [
        345, 606, 775, 924, 573, 178, 459, 192, 793, 310,
        167, 244, 197,  82, 571, 928, 585, 846, 527, 780,
    ]

    // (a) First 20 rng(1000) outputs from seed 0 must exactly match the 68k reference sequence.
    func testReferenceVector() {
        var rng = LCGRandomNumberGenerator(seed: 0)
        let computed = (0..<20).map { _ in rng.rng(1000) }
        XCTAssertEqual(computed, referenceVector,
            "rng(1000) from seed 0 must match the 68k A5+0xa2 reference sequence")
    }

    // (b) rng(100) over 10 000 calls always falls in [0, 100).
    func testRangeInvariant() {
        var rng = LCGRandomNumberGenerator(seed: 0)
        for i in 0..<10_000 {
            let v = rng.rng(100)
            XCTAssert(v >= 0 && v < 100, "rng(100) out of range at call \(i): \(v)")
        }
    }

    // (c) Two generators with the same seed produce identical sequences.
    func testDeterminism() {
        var rng1 = LCGRandomNumberGenerator(seed: 42)
        var rng2 = LCGRandomNumberGenerator(seed: 42)
        let seq1 = (0..<50).map { _ in rng1.rng(1000) }
        let seq2 = (0..<50).map { _ in rng2.rng(1000) }
        XCTAssertEqual(seq1, seq2,
            "Two generators with the same seed must produce identical sequences")
    }
}
