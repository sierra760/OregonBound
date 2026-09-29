import XCTest
@testable import OregonBound

final class NewGameInitTests: XCTestCase {

    private func makeGame(profession: Int, partySize: Int = 1, seed: UInt32 = 0) -> GameState {
        var rng = LCGRandomNumberGenerator(seed: seed)
        return GameState.newGame(profession: profession, partySize: partySize, rng: &rng)
    }

    // All professions 1–8 must produce startingYear == 1848.
    func testStartingYearAllProfessions() {
        for p in 1...8 {
            let gs = makeGame(profession: p)
            XCTAssertEqual(gs.startingYear, 1848, "profession \(p): startingYear must be 1848")
        }
    }

    // profession 1: distanceToNext = (8-1)*100 + rng(100) → [700, 800).
    func testDistanceBoundsProfession1() {
        for seed: UInt32 in 0..<100 {
            let gs = makeGame(profession: 1, seed: seed)
            XCTAssert(
                gs.distanceToNext >= 700 && gs.distanceToNext < 800,
                "profession 1 seed \(seed): distanceToNext \(gs.distanceToNext) not in [700,800)"
            )
        }
    }

    // profession 8: distanceToNext = (8-8)*100 + rng(100) → [0, 100).
    func testDistanceBoundsProfession8() {
        for seed: UInt32 in 0..<100 {
            let gs = makeGame(profession: 8, seed: seed)
            XCTAssert(
                gs.distanceToNext >= 0 && gs.distanceToNext < 100,
                "profession 8 seed \(seed): distanceToNext \(gs.distanceToNext) not in [0,100)"
            )
        }
    }

    // Doctor (profession 3) receives rng(1200) headstart; with seed 0 yields 775 > 0.
    func testDoctorHeadstartBonus() {
        let gs = makeGame(profession: 3, seed: 0)
        XCTAssert(gs.milesTraveled > 0, "Doctor must start with milesTraveled > 0 from rng(1200) bonus")
        XCTAssert(gs.milesTraveled < 1200, "Doctor headstart must be < 1200")
    }

    // Non-doctor professions get no headstart bonus.
    func testNonDoctorNoHeadstart() {
        let gs = makeGame(profession: 1)
        XCTAssertEqual(gs.milesTraveled, 0, "Non-doctor must start with milesTraveled == 0")
    }

    // Identical seed produces identical GameState (determinism via Equatable).
    func testDeterminism() {
        let gs1 = makeGame(profession: 4, seed: 99)
        let gs2 = makeGame(profession: 4, seed: 99)
        XCTAssertEqual(gs1, gs2, "Same seed must produce identical GameState")
    }

    // activePartyCount and players.count both reflect the requested partySize.
    func testPartySizeInitialization() {
        for size in 1...5 {
            let gs = makeGame(profession: 2, partySize: size)
            XCTAssertEqual(gs.activePartyCount, size, "activePartyCount must equal partySize \(size)")
            XCTAssertEqual(gs.players.count, size, "players.count must equal partySize \(size)")
        }
    }
}
