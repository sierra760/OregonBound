import XCTest
@testable import OregonBound

final class ConfigLoaderTests: XCTestCase {

    private var testBundle: Bundle { Bundle(for: type(of: self)) }

    // MARK: - GameLoopConstants

    func testGameLoopConstantsLoads() throws {
        let constants = try ConfigLoader.load(GameLoopConstants.self,
                                              resource: "game_loop_constants",
                                              bundle: testBundle)
        XCTAssertEqual(constants.game_initialization.starting_year.value, 1848)
        XCTAssertEqual(constants.game_initialization.max_party_size.value, 32)
    }

    func testGameLoopConstantsAllSectionsPopulated() throws {
        let constants = try ConfigLoader.load(GameLoopConstants.self,
                                              resource: "game_loop_constants",
                                              bundle: testBundle)
        XCTAssertFalse(constants.game_state_block_layout.isEmpty)
        XCTAssertFalse(constants.weather_system.isEmpty)
        XCTAssertFalse(constants.illness_system.isEmpty)
        XCTAssertFalse(constants.a5_jump_table_entries.isEmpty)
    }

    // MARK: - SubsystemConstants

    func testSubsystemConstantsLoads() throws {
        let constants = try ConfigLoader.load(SubsystemConstants.self,
                                              resource: "subsystem_constants",
                                              bundle: testBundle)
        XCTAssertFalse(constants.hunt_minigame.isEmpty)
    }

    func testSubsystemConstantsAllSectionsPresent() throws {
        let constants = try ConfigLoader.load(SubsystemConstants.self,
                                              resource: "subsystem_constants",
                                              bundle: testBundle)
        XCTAssertFalse(constants.river_crossing.isEmpty)
        XCTAssertFalse(constants.raft_crossing.isEmpty)
        XCTAssertFalse(constants.shopping.isEmpty)
        XCTAssertFalse(constants.ending_scoring.isEmpty)
    }

    // MARK: - Error handling

    func testLoadNonexistentResourceThrows() {
        XCTAssertThrowsError(
            try ConfigLoader.load(GameLoopConstants.self,
                                  resource: "does_not_exist",
                                  bundle: testBundle)
        )
    }
}
