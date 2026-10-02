import Foundation
import Testing
@testable import OregonBound

struct CDNotificationRulesTests {
    @Test func modelRecordsTypedNotificationParametersWithoutChangingJournalOrRNG() {
        var cd = Journey(seed: 17, edition: .macintoshCD12)
        var classic = Journey(seed: 17, edition: .macintosh11)
        for code in [22,26,27,30,33,34,37,38,42,52,63,69] {
            OriginalTrailEvents.record(code, part: .axles, in: &cd)
            if code != 69 { OriginalTrailEvents.record(code, part: .axles, in: &classic) }
        }
        let events = cd.journal.compactMap(\.cdNotification)
        #expect(events == [.init(code:23), .init(code:26,parameter:0), .init(code:26,parameter:1),
            .init(code:47,parameter:4), .init(code:47,parameter:4), .init(code:47,parameter:4),
            .init(code:37,parameter:3), .init(code:37,parameter:4), .init(code:37,parameter:8),
            .init(code:63), .init(code:69)])
        #expect(classic.journal.allSatisfy { $0.cdNotification == nil })
        #expect(cd.randomState == 17 && classic.randomState == 17)
        #expect(cd.journal.count == 12 && classic.journal.count == 11)
        #expect(Array(cd.journal.prefix(11)).map(\.text) == classic.journal.map(\.text))
    }

    @Test func notificationMetadataRoundTripsAndOldEntriesStayAbsent() throws {
        var trip = Journey(seed: 9, edition: .macintoshCD12)
        OriginalTrailEvents.record(27, in: &trip)
        let data = try JSONEncoder().encode(trip)
        let loaded = try JSONDecoder().decode(Journey.self, from: data)
        #expect(loaded.journal.last?.cdNotification == .init(code:26,parameter:1))
        var object = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        var entries = object["journal"] as! [[String:Any]]
        for index in entries.indices { entries[index].removeValue(forKey:"cdNotification") }
        object["journal"] = entries
        let older = try JSONDecoder().decode(Journey.self, from: JSONSerialization.data(withJSONObject:object))
        #expect(older.journal.allSatisfy { $0.cdNotification == nil })
        #expect(older.journal.map(\.text) == trip.journal.map(\.text))
    }

    private let clear = CDNotificationRules.Context(weather: 0, snow: 0, destination: 5)

    @Test func priorityAndOrdinaryEventsCompeteWithinOneDay() {
        var state = CDNotificationRules.State()
        state.beginBatch()
        state.receive(.init(code: 0), in: clear)
        state.receive(.init(code: 9), in: clear) // Low priority cannot replace fog.
        #expect(state.selected?.art == 0 && state.selected?.sound == 4005)
        state.receive(.init(code: 26, parameter: 0), in: clear)
        state.receive(.init(code: 65), in: clear) // Fire cannot replace a priority injury.
        #expect(state.selected?.art == 18 && state.selected?.priority == true)
        state.receive(.init(code: 24), in: clear) // Later priority wins.
        #expect(state.selected?.art == 25)
        state.beginBatch()
        #expect(state.selected == nil)
        state.receive(.init(code: 65), in: clear)
        #expect(state.selected?.art == 1 && state.selected?.cycle == true)
    }

    @Test func destinationGuardsPersistAcrossBatchesAndUseRawDestination() {
        var state = CDNotificationRules.State()
        let start = CDNotificationRules.Context(weather: 0, snow: 0, destination: 0)
        state.receive(.init(code: 25), in: start)
        #expect(state.selected == nil)
        state.receive(.init(code: 25), in: clear)
        #expect(state.selected?.art == 26)
        state.beginBatch(); state.receive(.init(code: 25), in: clear)
        #expect(state.selected == nil)
        state.receive(.init(code: 25), in: .init(weather: 0, snow: 0, destination: 6))
        #expect(state.selected?.art == 26)
        state.beginBatch(); state.receive(.init(code: 9), in: clear)
        #expect(state.selected?.art == 11) // Independent guard for bad water.
    }

    @Test func foodAidVariantsAdvanceWithinTheBatchWithoutRandomness() {
        var state = CDNotificationRules.State()
        var frames: [Int] = []
        for _ in 0..<8 { state.receive(.init(code: 20), in: clear); frames.append(state.selected!.art) }
        #expect(frames == [28,29,30,31,33,35,28,29])
        state.beginBatch()
        state.receive(.init(code: 20), in: clear)
        #expect(state.selected?.art == 28)
        let snow = CDNotificationRules.Context(weather: 0, snow: 1, destination: 5)
        state.receive(.init(code: 20), in: snow); #expect(state.selected?.art == 32)
        state.receive(.init(code: 20), in: snow); #expect(state.selected?.art == 34)
    }

    @Test func snowboundRetainsLastCandidateSoundEvenWhenThatCandidateLostSelection() {
        var state = CDNotificationRules.State()
        state.receive(.init(code: 12), in: clear)
        #expect(state.selected?.art == 44 && state.selected?.sound == 0)
        state.receive(.init(code: 26), in: clear)
        state.receive(.init(code: 8), in: clear) // Candidate sound4004, rejected by injury priority.
        #expect(state.selected?.art == 18)
        state.beginBatch(); state.receive(.init(code: 12), in: clear)
        #expect(state.selected?.sound == 4004 && state.selected?.external == false)
    }

    @Test func weatherAndParameterVariantsChooseTheirGuideAndSound() {
        var state = CDNotificationRules.State()
        state.receive(.init(code: 26, parameter: 1), in: .init(weather: 2, snow: 0, destination: 5))
        #expect(state.selected?.art == 61)
        state.beginBatch(); state.receive(.init(code: 24), in: .init(weather: 3, snow: 1, destination: 5))
        #expect(state.selected?.art == 22) // Rain wins over snow in this branch.
        state.beginBatch(); state.receive(.init(code: 47, parameter: 5), in: clear)
        #expect(state.selected?.art == 20 && state.selected?.guide == 68 && state.selected?.sound == 4012)
        state.beginBatch(); state.receive(.init(code: 37, parameter: 6), in: clear)
        #expect(state.selected?.art == 60 && state.selected?.guide == 45)
        state.beginBatch(); state.receive(.init(code: 29), in: clear)
        #expect(state.selected?.art == 2 && state.selected?.guide == 61 && state.selected?.external == true)
        state.beginBatch(); state.receive(.init(code: 34), in: clear)
        #expect(state.selected == nil) // Journal broken-part opcode is not a notification opcode.
    }
}
