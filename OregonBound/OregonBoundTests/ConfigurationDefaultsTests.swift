import Foundation
import Testing
@testable import OregonBound

struct ConfigurationDefaultsTests {
    static func fixture() -> Data {
        var data = Data(repeating: 0, count: 1108)
        data.replaceSubrange(0x26..<0x2a, with: [3, 65, 0x8e, 66])
        data.replaceSubrange(0x126..<0x12a, with: [3, 75, 101, 121])
        data[0x135] = 8; data[0x136] = 6
        return data
    }
    @Test func decodesAndMapsSourceDefaults() throws {
        let defaults = try ConfigurationExtractor.parse(Self.fixture())
        #expect(defaults.hint == "AéB")
        #expect(defaults.password == "Key")
        #expect(defaults.speed == 8 && defaults.huntTime == 6)
        let configuration = OriginalPreferences.Configuration(defaults: defaults)
        #expect(configuration.hint == defaults.hint)
        #expect(configuration.accepts(password: "KEY"))
        #expect(configuration.timing == .init(speed: .slow, huntTime: .minutes2))
        #expect(try JSONDecoder().decode(ConfigurationExtractor.Defaults.self, from: JSONEncoder().encode(defaults)) == defaults)
    }
    @Test(arguments: ["short", "long", "password", "empty", "speed", "hunt"])
    func rejectsInvalidSource(kind: String) {
        var data = Self.fixture()
        switch kind {
        case "short": data.removeLast()
        case "long": data.append(0)
        case "password": data[0x126] = 11
        case "empty": data[0x126] = 0
        case "speed": data[0x135] = 3
        default: data[0x136] = 7
        }
        #expect(throws: (any Error).self) { try ConfigurationExtractor.parse(data) }
    }
    @Test(arguments: ["password", "hint", "speed", "huntTime"])
    func rejectsInvalidPreparedSettings(field: String) throws {
        var value: [String: Any] = ["password": "Key", "hint": "Example", "speed": 4, "huntTime": 3]
        switch field {
        case "password": value[field] = String(repeating: "x", count: 11)
        case "hint": value[field] = "🛶"
        default: value[field] = 0
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ConfigurationExtractor.Defaults.self, from: data) }
    }
}
