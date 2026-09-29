import Foundation

/// MENU1001 and the executable's explicit item enable/disable operations.
enum OriginalFileMenuRules {
    enum Item: Int, Hashable, CaseIterable { case load = 1, save = 2, exportLog = 4, exitGame = 6, quit = 7 }
    enum Stage: Int { case attract = 0, setup = 1, journey = 2 }
    struct State: Equatable {
        private(set) var enabled: Set<Item> = [.load, .quit] // MENU1001 mask0x83
        private(set) var windowInactive = false // A5−2044, cleared at CODE1:195c.
        func permits(_ item: Item) -> Bool { enabled.contains(item) }
        /// CODE1:1a42–1a4e /1a8c–1a98 toggles item0 of Game1003 and Management1004.
        var permitsGameMenus: Bool { !windowInactive }
        mutating func leaveAttractViaButton() { enabled.remove(.exportLog) }
        mutating func beginSetup() { enabled.insert(.exitGame); enabled.remove(.load) }
        mutating func beginJourney() { enabled.formUnion([.save, .exportLog, .exitGame]); enabled.remove(.load) }
        mutating func beginBlockingActivity() { enabled.subtract([.save, .exportLog, .exitGame, .quit]) }
        mutating func endBlockingActivity() { enabled.formUnion([.save, .exportLog, .exitGame, .quit]) }
        mutating func beginEnding() { enabled.subtract([.save, .exitGame]); enabled.insert(.exportLog) }
        mutating func enterAttract(hasExportText: Bool) {
            enabled.subtract([.save, .exitGame]); enabled.formUnion([.load, .quit])
            if hasExportText { enabled.insert(.exportLog) } else { enabled.remove(.exportLog) }
        }
        /// CODE1:19ec rejects other windows; 1a02/1a62 reject duplicate states.
        /// Real focus edges change these two File items only. A modal overlay
        /// is not itself an activation event and must not synthesize this call.
        mutating func activateWindow(_ active: Bool, stage: Stage, isGameWindow: Bool = true) {
            guard isGameWindow, active == windowInactive else { return }
            windowInactive = !active
            enabled.subtract([.load, .exitGame])
            if active { enabled.insert(stage == .attract ? .load : .exitGame) }
        }
    }
    enum Departure: String { case exitGame = "exiting", quit = "quitting" }
    enum Choice { case yes, no }
    enum SaveResult { case saved, cancelled, failed }
    enum Action: Equatable { case depart, askToSave, chooseSaveFile, showTimeOutRequired, restoreJourney }
    static let timeOutRequired = "You can only save a game during a time out."
    static func requestDeparture(stage: Stage) -> Action { stage == .journey ? .askToSave : .depart }
    static func respond(_ choice: Choice, moving: Bool) -> Action {
        if choice == .no { return .depart }
        return moving ? .showTimeOutRequired : .chooseSaveFile
    }
    static func afterSave(_ result: SaveResult) -> Action { result == .saved ? .depart : .restoreJourney }
    static func saveAction(moving: Bool) -> Action { moving ? .showTimeOutRequired : .chooseSaveFile }
    static func question(_ departure: Departure) -> String { "Do you want to save this game before \(departure.rawValue)?" }
}

/// CODE11:015a/0202, CODE14:2328 and CODE3:0e16. Input is already formatted,
/// visibility-filtered original records, NOT modern per-event date prefixes.
enum OriginalTrailLogExport {
    static let suggestedFilename = "Trail Log"
    static let chooserPrompt = "Export log to:"
    static let finderType: UInt32 = 0x54455854 // TEXT
    static let finderCreator: UInt32 = 0x74747874 // ttxt
    enum ExportError: Error { case unrepresentableText, recordTooLong }
    struct Record { var text: String; var visible = true; var appendCarriageReturn = true }
    static func dateHeader(year: UInt16, monthName: String, day: UInt8) -> String {
        // CODE14:239c sign-extends the year WORD; preserve that rare boundary.
        "• \(monthName) \(day), \(Int16(bitPattern: year)) •"
    }
    static func data(records: [Record]) throws -> Data {
        var buffer = Data()
        for record in records where record.visible {
            guard var line = record.text.data(using: .macOSRoman) else { throw ExportError.unrepresentableText }
            guard line.count <= 255 else { throw ExportError.recordTooLong }
            // The Pascal append routine wraps its length byte. A255-byte
            // record plus CR has length0 and contributes no bytes.
            if record.appendCarriageReturn {
                if line.count == 255 { line.removeAll() } else { line.append(13) }
            }
            // CODE11 checks EXISTING hText size, then deletes through
            // TERec.lineStarts[8] (offset0x70); crOnly=-1 disables soft wraps.
            if buffer.count > 32_000 {
                var breaks = 0
                var end = buffer.startIndex
                for index in buffer.indices {
                    end = buffer.index(after: index)
                    if buffer[index] == 13 { breaks += 1; if breaks == 8 { break } }
                }
                buffer.removeSubrange(buffer.startIndex..<end)
            }
            buffer.append(line)
        }
        return buffer
    }
}
