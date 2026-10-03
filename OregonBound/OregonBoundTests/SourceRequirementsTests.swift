import Foundation
import Testing
@testable import OregonBound

struct SourceRequirementsTests {
    private func fork(_ identities: [(String, Int)]) -> MacResourceFork {
        MacResourceFork(resources: identities.map { MacResource(type: $0.0, id: $0.1, name: nil, attributes: 0, data: Data([1])) })
    }

    @Test func completeIdentitySetsAcceptReorderedResources() throws {
        try GameSourceRequirements.validate(fork([("Imag", 9), ("STR#", 2), ("Imag", 7)]), role: .graphics1,
                                            required: ["Imag": [7, 9], "STR#": [2]])
    }
    @Test func missingAndUnexpectedIdentitiesAreRejected() {
        for identities: [(String, Int)] in [[("Imag", 7)], [("Imag", 7), ("Imag", 9), ("Imag", 10)],
                                           [("Imag", 7), ("Imag", 9), ("Ima4", 7)], [("Imag", 7), ("Imag", 7), ("Imag", 9)]] {
            #expect(throws: (any Error).self) {
                try GameSourceRequirements.validate(fork(identities), role: .graphics1, required: ["Imag": [7, 9]])
            }
        }
    }
    @Test func everyRequiredRoleHasAProfile() {
        for edition in GameEdition.allCases {
            for role in edition.requiredRoles {
                #expect(!GameSourceRequirements.resources(for: role).isEmpty)
            }
        }
        #expect(GameSourceRequirements.resources(for: .graphics1)["Imag"]?.count == 259)
        #expect(GameSourceRequirements.resources(for: .graphics2)["TERR"]?.count == 30)
        #expect(GameSourceRequirements.resources(for: .graphics3)["Ima4"]?.count == 228)
        #expect(GameSourceRequirements.resources(for: .guide3)["snd "] == Set(6050...6073))
    }
}
