import Foundation
import Testing
@testable import OregonBound

struct OriginalPreferencesTests {
    @Test func configurationAndWorldTimingAreIndependent() {
        var configuration = OriginalPreferences.Configuration()
        let active = configuration.beginJourney()
        configuration.timing = .init(speed: .fast, huntTime: .minutes2)
        #expect(active == .init())
        #expect(configuration.beginJourney().timerThreshold == 2)
        #expect(configuration.beginJourney().huntSelector == 6)
        #expect(active.simulationDayTicks == 300)
        #expect(active.travelAnimationTicks == 240)
        #expect(active.huntDurationTicks == 2700)
    }
    @Test func allTimingChoices() {
        #expect(OriginalPreferences.Speed.allCases.map(\.rawValue) == [2, 4, 8])
        #expect(OriginalPreferences.HuntTime.allCases.map(\.seconds) == [20, 30, 45, 60, 90, 120])
    }
    @Test func managementStartsLockedAndWrongPasswordDoesNotUnlock() {
        let configuration = OriginalPreferences.Configuration()
        var session = OriginalPreferences.ManagementSession()
        #expect(session.permits(.about))
        #expect(!session.permits(.timeOptions))
        let rejected = session.enable(password: "wrong", configuration: configuration)
        #expect(!rejected)
        #expect(!session.enabled)
        let accepted = session.enable(password: "BOoM", configuration: configuration)
        #expect(accepted)
        #expect(session.permits(.clearLegends))
        #expect(!session.permits(.clearLegends, networkUser: true))
        #expect(session.permits(.changePassword, networkUser: true))
        session.disable()
        #expect(!session.permits(.changePassword))
    }
    @Test func changingPasswordRequiresOldPasswordAndRejectsBlank() {
        var configuration = OriginalPreferences.Configuration()
        #expect(configuration.changePassword(old: "wrong", new: "hello", hint: "bad") == .incorrect)
        #expect(configuration.changePassword(old: "boom", new: "", hint: "bad") == .empty)
        #expect(configuration.hint == "See the Oregon Trail User’s Guide.")
        #expect(configuration.changePassword(old: "BOOM", new: "1234567890123", hint: "") == nil)
        #expect(configuration.password == "1234567890")
        #expect(!configuration.accepts(password: "boom"))
        #expect(configuration.hint.isEmpty)
        #expect(OriginalPreferences.typedPassword("a b\ncé!123456789", maximumLength: 10) == "abc!123456")
    }
    @Test func settingsRoundTripButRuntimeUnlockDoesNotPersist() throws {
        var configuration = OriginalPreferences.Configuration()
        configuration.timing = .init(speed: .slow, huntTime: .seconds90)
        _ = configuration.changePassword(old: "boom", new: "TRAIL", hint: "A road")
        let encoded = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(OriginalPreferences.Configuration.self, from: encoded)
        #expect(restored == configuration)
        #expect(!OriginalPreferences.ManagementSession().enabled)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("enabled"))
        let invalid = Data(#"{"timing":{"speed":0,"huntTime":3},"password":"boom","hint":""}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OriginalPreferences.Configuration.self, from: invalid) }
    }
    @Test func passwordAndHintCommitTruncateMacRomanBytesInsideCRLF() throws {
        var configuration = OriginalPreferences.Configuration()
        let password = String(repeating: "A", count: 9) + "\r\nB"
        let hint = String(repeating: "A", count: 254) + "\r\nB"
        #expect(configuration.changePassword(old: "boom", new: password, hint: hint) == nil)
        #expect(configuration.password == String(repeating: "A", count: 9) + "\r")
        #expect(configuration.hint == String(repeating: "A", count: 254) + "\r")
        #expect(configuration.password.data(using: .macOSRoman)?.count == 10)
        #expect(configuration.hint.data(using: .macOSRoman)?.count == 255)
        #expect(try JSONDecoder().decode(OriginalPreferences.Configuration.self,
            from: JSONEncoder().encode(configuration)) == configuration)
    }
    @Test func commitPreservesMacRomanAccentsAndPastedControlBytes() {
        var configuration = OriginalPreferences.Configuration()
        let password = "é\u{0}\t" + String(repeating: "ö", count: 8)
        let hint = String(repeating: "é", count: 300)
        #expect(configuration.changePassword(old: "boom", new: password, hint: hint) == nil)
        #expect(configuration.password == "é\u{0}\t" + String(repeating: "ö", count: 7))
        #expect(configuration.hint == String(repeating: "é", count: 255))
    }
    @Test func legacyUnicodeConfigurationStillLoadsAndKeepsItsFallbackCommit() throws {
        let legacy = Data(#"{"timing":{"speed":4,"huntTime":3},"password":"🌲","hint":"A trail 🦬"}"#.utf8)
        var configuration = try JSONDecoder().decode(OriginalPreferences.Configuration.self, from: legacy)
        #expect(configuration.accepts(password: "🌲"))
        #expect(configuration.hint == "A trail 🦬")
        #expect(configuration.changePassword(old: "🌲", new: String(repeating: "🌲", count: 11),
            hint: String(repeating: "🦬", count: 256)) == nil)
        #expect(configuration.password == String(repeating: "🌲", count: 10))
        #expect(configuration.hint == String(repeating: "🦬", count: 255))
        #expect(try JSONDecoder().decode(OriginalPreferences.Configuration.self,
            from: JSONEncoder().encode(configuration)) == configuration)
    }
    @Test func introductionUsesThreePicturesAndBoundedNavigation() {
        var page = OriginalPreferences.Introduction()
        page.previous()
        #expect(page.pictureResource == 2050)
        #expect(!page.canGoPrevious && !page.doneIsDefault)
        page.next()
        #expect(page.pictureResource == 2051)
        page.next(); page.next()
        #expect(page.pictureResource == 2052)
        #expect(!page.canGoNext && page.doneIsDefault)
        page.previous()
        #expect(page.page == 2)
    }
}
