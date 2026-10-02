import Foundation
import Testing
@testable import OregonBound

struct OriginalFileMenuTests {
    @Test func originalMenuLifecycleAndActivityLocks() {
        var menu = OriginalFileMenuRules.State()
        #expect(menu.enabled == [.load, .quit])
        menu.beginSetup()
        #expect(menu.enabled == [.exitGame, .quit])
        menu.beginJourney()
        #expect(menu.enabled == [.save, .exportLog, .exitGame, .quit])
        menu.beginBlockingActivity()
        #expect(menu.enabled.isEmpty)
        menu.endBlockingActivity()
        #expect(menu.enabled == [.save, .exportLog, .exitGame, .quit])
        menu.beginEnding()
        #expect(menu.enabled == [.exportLog, .quit])
        menu.enterAttract(hasExportText: true)
        #expect(menu.enabled == [.load, .exportLog, .quit])
        menu.enterAttract(hasExportText: false)
        #expect(menu.enabled == [.load, .quit])
    }
    @Test func movingSaveIsAnActionRejectionAndCancelDoesNotExit() {
        #expect(OriginalFileMenuRules.requestDeparture(stage: .journey) == .askToSave)
        #expect(OriginalFileMenuRules.requestDeparture(stage: .setup) == .depart)
        #expect(OriginalFileMenuRules.respond(.yes, moving: true) == .showTimeOutRequired)
        #expect(OriginalFileMenuRules.respond(.no, moving: true) == .depart)
        #expect(OriginalFileMenuRules.respond(.yes, moving: false) == .chooseSaveFile)
        #expect(OriginalFileMenuRules.afterSave(.cancelled) == .restoreJourney)
        #expect(OriginalFileMenuRules.afterSave(.failed) == .restoreJourney)
        #expect(OriginalFileMenuRules.afterSave(.saved) == .depart)
    }
    @Test func exportUsesMacRomanCarriageReturnsAndSeparateDateHeader() throws {
        let header = OriginalTrailLogExport.dateHeader(year: 1848, monthName: "March", day: 1)
        let data = try OriginalTrailLogExport.data(records: [.init(text: header), .init(text: "Hidden", visible: false), .init(text: "You decided to hunt.")])
        #expect(data.first == 0xa5)
        #expect(!data.contains(10))
        #expect(String(data: data, encoding: .macOSRoman) == "• March 1, 1848 •\rYou decided to hunt.\r")
        #expect(OriginalTrailLogExport.dateHeader(year: 65535, monthName: "December", day: 31) == "• December 31, -1 •")
    }
    @Test func exportBufferDropsEightHardLinesBeforeTheNextAppend() throws {
        let record = OriginalTrailLogExport.Record(text: String(repeating: "x", count: 249))
        let atBoundary = try OriginalTrailLogExport.data(records: Array(repeating: record, count: 128))
        #expect(atBoundary.count == 32_000)
        let afterOneMore = try OriginalTrailLogExport.data(records: Array(repeating: record, count: 129))
        #expect(afterOneMore.count == 32_250)
        let afterTrim = try OriginalTrailLogExport.data(records: Array(repeating: record, count: 130))
        #expect(afterTrim.count == 30_500)
        #expect(afterTrim.filter { $0 == 13 }.count == 122)
    }
    @Test func exportPreservesPascalOverflowWithoutMemoryCorruption() throws {
        let data = try OriginalTrailLogExport.data(records: [.init(text: String(repeating: "a", count: 255)), .init(text: "end")])
        #expect(data == Data("end\r".utf8))
        #expect(throws: OriginalTrailLogExport.ExportError.self) {
            try OriginalTrailLogExport.data(records: [.init(text: String(repeating: "a", count: 256))])
        }
        #expect(throws: OriginalTrailLogExport.ExportError.self) {
            try OriginalTrailLogExport.data(records: [.init(text: "🌲")])
        }
    }
    @Test func aboutDoubleClickUsesSuppliedThresholdAndResetsPair() {
        var about = OriginalAboutRules.State()
        about.clickLogo(tick: 100, doubleClickTicks: 30)
        about.clickLogo(tick: 129, doubleClickTicks: 30)
        #expect(about.showsSystemInformation)
        about.clickLogo(tick: 130, doubleClickTicks: 30)
        #expect(about.showsSystemInformation)
        about.clickLogo(tick: 160, doubleClickTicks: 30)
        #expect(about.showsSystemInformation) // equality is not double-click
        about.clickLogo(tick: 161, doubleClickTicks: 30)
        #expect(!about.showsSystemInformation)
        let positions = OriginalAboutRules.creditPositions(width: { $0.count })
        #expect(positions.count == 13)
        #expect(positions[0].baseline == 12 && positions[6].baseline == 108)
        #expect(positions[7].baseline == 12 && positions[12].baseline == 92)
        #expect(positions[7].x == 34)
    }
    @Test func cdCreditScrollStartsBlankCopiesOneRowAndWrapsWithoutCatchup() throws {
        var scroll = try OriginalAboutRules.CreditsScroll(bufferHeight: 130)
        #expect(scroll.sourceRow(at: 0) == nil && scroll.sourceRow(at: 114) == nil)
        scroll.advance()
        #expect(scroll.sourceRow(at: 113) == nil && scroll.sourceRow(at: 114) == 0)
        for _ in 1..<115 { scroll.advance() }
        #expect(scroll.sourceRow(at: 0) == 0 && scroll.sourceRow(at: 114) == 114)
        for _ in 115..<130 { scroll.advance() }
        #expect(scroll.sourceRow(at: 0) == 15 && scroll.sourceRow(at: 114) == 129)
        scroll.advance()
        #expect(scroll.sourceRow(at: 0) == 16 && scroll.sourceRow(at: 114) == 0)
        #expect(scroll.sourceRow(at: -1) == nil && scroll.sourceRow(at: 115) == nil)
        scroll.reset()
        #expect(scroll.sourceRow(at: 0) == nil && scroll.sourceRow(at: 114) == nil)
        scroll.advance()
        #expect(scroll.sourceRow(at: 114) == 0)
        #expect(throws: (any Error).self) { try OriginalAboutRules.CreditsScroll(bufferHeight: 114) }
        #expect(throws: (any Error).self) { try OriginalAboutRules.CreditsScroll(bufferHeight: 32768) }
    }

}
