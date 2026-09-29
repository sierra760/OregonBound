import Foundation
import Testing
@testable import OregonBound

struct OriginalHuntNoticeIntegrationTests {
    @Test(.enabled(if: GameData.isReady)) @MainActor func landmarkNoticeRemainsUntilDismissedAndDoesNotMutateJourney() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1)
        trip.locationID = "kansas"; trip.destinationID = "kansas"; trip.phase = .river
        trip.inventory[.bullets] = 100
        game.trip = trip
        game.startHunt()
        #expect(game.trip == trip)
        #expect(game.actionNotice?.text == "Hunting is not allowed near the Kansas River Crossing, because there are too many people around")
        #expect(game.actionNotice?.ticks == nil)
        #expect(game.error == nil)
        game.dismissActionNotice()
        #expect(game.actionNotice == nil)
    }
    @Test @MainActor func severeWeatherPrecedesNoAmmoAndUsesFiveSecondNotice() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1)
        trip.phase = .travel; trip.original?.weather.category = 7
        trip.inventory[.bullets] = 0
        game.trip = trip
        game.startHunt()
        #expect(game.actionNotice?.text == "You can’t go hunting because the weather is too severe")
        #expect(game.actionNotice?.ticks == 300)
        #expect(game.trip == trip)
        #expect(game.error == nil)
    }
}
