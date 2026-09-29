import Foundation
import Testing
@testable import OregonBound

struct OriginalRegistrationJourneyTests {
    @Test func acceptedRegistrationNamesSurviveModelAndSaveWithoutNormalization() throws {
        let names = try OriginalRegistration.commitNames(leader: "  Zoë  ",
            companions: ["", " André ", "   ", String(repeating: "x", count: 16)])
        var trip = Journey(names: names, seed: 42)
        #expect(trip.members.map(\.name) == ["  Zoë  ", " André ", "   "])
        try JourneyStore().validate(trip)
        trip = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(trip.members.map(\.name) == names)
    }

    @Test func legacyProgrammaticFallbackRemainsSeparateFromRegistration() {
        #expect(Journey(names: [], seed: 42).members.map(\.name) == ["Traveler"])
        #expect(Journey(names: [""], seed: 42).members.map(\.name) == ["Traveler 1"])
        #expect(throws: OriginalRegistration.ValidationError.self) {
            try OriginalRegistration.commitNames(leader: "", companions: [])
        }
    }
}
