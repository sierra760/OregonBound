import Foundation
import Testing
@testable import OregonBound

struct TerrainExtractorTests {
    private func words(_ values: [Int16]) -> Data {
        var data = Data()
        for value in values { data.appendU16(UInt16(bitPattern: value)) }
        return data
    }

    @Test func permissionsAndAbsoluteBoundsArePreserved() throws {
        let terrain = try TerrainExtractor.parse(words([2, 0, 2, -3, 5, 9, 20, 10, 21, 30, 45]), resourceID: 17)
        #expect(terrain.resourceID == 17)
        #expect(terrain.leftEntryAllowed && !terrain.rightEntryAllowed)
        #expect(terrain.obstacles.count == 2)
        #expect(terrain.obstacles[0].top == -3)
        #expect(terrain.obstacles[1].right == 45)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(terrain)) as? [String: Any])
        #expect(object["resource_id"] as? Int == 17)
        #expect(object["left_entry_allowed"] as? Bool == true)
    }

    @Test func emptyTerrainAcceptsAnyNonzeroPermission() throws {
        let terrain = try TerrainExtractor.parse(words([0, -1, 0]), resourceID: 18)
        #expect(!terrain.leftEntryAllowed && terrain.rightEntryAllowed)
        #expect(terrain.obstacles.isEmpty)
    }

    @Test func incompleteExtraNegativeAndEmptyBoundsAreRejected() {
        let inputs = [Data(), Data(repeating: 0, count: 5), words([1, 1, -1]), words([1, 1, 1]),
                      words([1, 1, 0, 0]), words([1, 1, 1, 4, 2, 4, 7]), words([1, 1, 1, 1, 9, 8, 2])]
        for input in inputs {
            #expect(throws: (any Error).self) { try TerrainExtractor.parse(input, resourceID: 19) }
        }
    }
}
