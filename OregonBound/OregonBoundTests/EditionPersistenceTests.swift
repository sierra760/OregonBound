import Foundation
import Testing
@testable import OregonBound

struct EditionPersistenceTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func absentSessionUsesClassicDefaultsAndRequiresCDDefaults() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let classic = JourneyStore(directory: root, edition: .macintosh11, session: nil)
        #expect(try classic.preferences() == OriginalPreferences.Configuration())
        let cd = JourneyStore(directory: root, edition: .macintoshCD12, session: nil)
        #expect(throws: GameRuleError.self) { try cd.preferences() }
        var supplied = OriginalPreferences.Configuration()
        supplied.timing = .init(speed: .slow, huntTime: .minutes2)
        for edition in GameEdition.allCases {
            let store = JourneyStore(directory: root, edition: edition,
                                     defaultPreferences: supplied, session: nil)
            #expect(try store.preferences() == supplied)
        }
    }
    @Test(arguments: [UInt8(10), UInt8(0x8a)])
    func cdDustStormSaveReloadAndClassicRejection(category: UInt8) throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        for edition in [GameEdition.macintosh11, .macintoshCD12] {
            var trip = Journey(seed: 51, edition: edition)
            trip.original?.weather.category = category
            let store = JourneyStore(directory: root, edition: edition)
            if edition == .macintoshCD12 {
                try store.save(trip)
                #expect(try store.load() == trip)
            } else {
                #expect(throws: GameRuleError.self) { try store.validate(trip) }
            }
            trip.original?.weather.category = 11
            #expect(throws: GameRuleError.self) { try store.validate(trip) }
        }
    }

    @Test func storesSeparateFilesAndRejectForeignSavesWithoutReplacingThem() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let classic = JourneyStore(directory: root, edition: .macintosh11)
        let cd = JourneyStore(directory: root, edition: .macintoshCD12)
        let original = Journey(seed: 1), deluxe = Journey(seed: 2, edition: .macintoshCD12)
        try classic.save(original); try cd.save(deluxe)
        #expect(classic.saveURL == root.appendingPathComponent("journey.json"))
        #expect(cd.saveURL != classic.saveURL)
        #expect(try classic.load() == original)
        #expect(try cd.load() == deluxe)
        #expect(throws: GameRuleError.self) { try cd.load(from: classic.saveURL) }
        #expect(throws: GameRuleError.self) { try classic.load(from: cd.saveURL) }
        let before = try Data(contentsOf: cd.saveURL)
        #expect(throws: GameRuleError.self) { try cd.save(original) }
        #expect(try Data(contentsOf: cd.saveURL) == before)
    }
    @Test func legacySaveBelongsOnlyToClassicAndUpgradesOnWrite() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let classic = JourneyStore(directory: root, edition: .macintosh11)
        var body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Journey(seed: 1))) as? [String: Any])
        body.removeValue(forKey: "edition")
        try JSONSerialization.data(withJSONObject: ["format": "OregonBound", "version": 1, "journey": body]).write(to: classic.saveURL)
        let restored = try classic.load()
        #expect(restored.gameEdition == .macintosh11)
        #expect(throws: GameRuleError.self) { try JourneyStore(directory: root, edition: .macintoshCD12).load(from: classic.saveURL) }
        try classic.save(restored)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: classic.saveURL)) as? [String: Any])
        #expect(saved["version"] as? Int == 2)
        #expect(saved["edition"] as? String == GameEdition.macintosh11.rawValue)
    }
    @Test(arguments: ["missing", "unknown", "version", "body", "legacy_tag"])
    func rejectsInvalidEditionEnvelopes(kind: String) throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintosh11)
        try store.save(Journey(seed: 1))
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.saveURL)) as? [String: Any])
        switch kind {
        case "missing": object.removeValue(forKey: "edition")
        case "unknown": object["edition"] = "future-edition"
        case "version": object["version"] = 99
        case "legacy_tag": object["version"] = 1; object["edition"] = GameEdition.macintoshCD12.rawValue
        default:
            var body = try #require(object["journey"] as? [String: Any]); body["edition"] = GameEdition.macintoshCD12.rawValue; object["journey"] = body
        }
        try JSONSerialization.data(withJSONObject: object).write(to: store.saveURL)
        #expect(throws: GameRuleError.self) { try store.load() }
    }
    @Test func preferencesAndLegendsAreEditionBound() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let classic = JourneyStore(directory: root, edition: .macintosh11)
        var custom = OriginalPreferences.Configuration(); custom.timing = .init(speed: .slow, huntTime: .minutes2)
        let cd = JourneyStore(directory: root, edition: .macintoshCD12, defaultPreferences: custom)
        #expect(try classic.preferences() == .init())
        #expect(try cd.preferences() == custom)
        #expect(throws: GameRuleError.self) { try JourneyStore(directory: root, edition: .macintoshCD12).preferences() }
        try cd.savePreferences(custom)
        #expect(try classic.preferences() == .init())
        try classic.removeLegends(classic.legends())
        #expect(try classic.legends().isEmpty)
        #expect(try cd.legends().count == 10)
        try cd.restoreOriginalLegends()
        for name in ["preferences.json", "hall-of-fame.json"] {
            let target = classic.directory.appendingPathComponent(name)
            try Data(contentsOf: cd.directory.appendingPathComponent(name)).write(to: target)
        }
        #expect(throws: GameRuleError.self) { try classic.preferences() }
        #expect(throws: GameRuleError.self) { try classic.legends() }
    }
    @Test func untaggedPreferencesAndScoresAreClassicOnly() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let classic = JourneyStore(directory: root, edition: .macintosh11)
        let cd = JourneyStore(directory: root, edition: .macintoshCD12)
        for store in [classic, cd] {
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(OriginalPreferences.Configuration()).write(to: store.directory.appendingPathComponent("preferences.json"))
            try Data("[]".utf8).write(to: store.directory.appendingPathComponent("hall-of-fame.json"))
        }
        #expect(try classic.preferences() == .init())
        #expect(try classic.legends().count == 10)
        #expect(throws: GameRuleError.self) { try cd.preferences() }
        #expect(throws: GameRuleError.self) { try cd.legends() }
    }
    @Test @MainActor func controllerCreatesJourneyForItsBoundStore() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12, defaultPreferences: .init())
        let game = GameController(store: store, random: OriginalRandomStream(seed: 1))
        game.start(profession: .banker, difficulty: .greenhorn, names: ["Test"], month: 4)
        #expect(game.trip?.gameEdition == .macintoshCD12)
        #expect(try store.load().gameEdition == .macintoshCD12)
    }
}
