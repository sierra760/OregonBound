import XCTest
@testable import OregonBound

final class OriginalRegistrationTests: XCTestCase {
    let pool = ["Zeke", "Jed", "Anna", "Mary", "Joey", "Beth", "John", "Sara", "Henry", "Emily"]
    func testTenFullRangeSwapsAndSkippedFirstSlot() {
        var calls = 0
        let names = OriginalRegistration.partyNames(pool: pool) { bound in
            XCTAssertEqual(bound, 10)
            defer { calls += 1 }
            return calls
        }
        XCTAssertEqual(calls, 10)
        XCTAssertEqual(names, ["", "Jed", "Anna", "Mary", "Joey"])
    }
    func testRepeatedRandomIndexStillProducesDistinctCompanions() {
        let names = OriginalRegistration.partyNames(pool: pool) { _ in 0 }
        XCTAssertEqual(names, ["", "Zeke", "Jed", "Anna", "Mary"])
    }

    func testLeaderLengthIsOneThroughFifteenMacRomanBytes() throws {
        XCTAssertFalse(OriginalRegistration.isValidName(""))
        XCTAssertTrue(OriginalRegistration.isValidName(String(repeating: "é", count: 15)))
        XCTAssertFalse(OriginalRegistration.isValidName(String(repeating: "é", count: 16)))
        XCTAssertFalse(OriginalRegistration.isValidName("🐂"))
        XCTAssertThrowsError(try OriginalRegistration.commitNames(leader: "", companions: []))
    }
    func testValidCompanionsCompactAcrossInvalidFields() throws {
        let names = try OriginalRegistration.commitNames(leader: "Leader", companions: ["", "Jane", String(repeating: "x", count: 16), "Pete"])
        XCTAssertEqual(names, ["Leader", "Jane", "Pete"])
        XCTAssertEqual(try OriginalRegistration.commitNames(leader: "Solo", companions: ["", "", "", ""]), ["Solo"])
    }
    func testCommitPreservesCaseAndWhitespaceWithoutFallback() throws {
        XCTAssertEqual(try OriginalRegistration.commitNames(leader: "  eD  ", companions: [" ", " aB "]), ["  eD  ", " ", " aB "])
        XCTAssertThrowsError(try OriginalRegistration.commitNames(leader: "Ed", companions: Array(repeating: "A", count: 5)))
    }
}
