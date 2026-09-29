import Foundation

/// App-owned portions of CODE15's modal TextEdit filters, not a replacement for
/// System7 TEKey/ModalDialog. Indices and lengths are Mac Roman bytes.
enum OriginalManagementTextEdit {
    static let fontResource = 5478 // Reference System7 Chicago12, plain.
    static let hintWidth = 135
    static let hintHeight = 48
    static let maximumHintLines = 3
    static let changedPasswordByteLimit = 10
    static let maskByte: UInt8 = 0xa5

    enum Field: Equatable, Sendable { case oldPassword, newPassword, hint, enablePassword }
    enum EventKind: Equatable, Sendable { case keyDown, autoKey }
    enum EncodingError: Error { case notMacRoman }
    enum Action: Equatable, Sendable {
        /// Return false from the custom filter, with this event character.
        case forwardToDialog(UInt8)
        /// CODE1:0400–0494 advances edit items and selects0...32767.
        case selectAll(Field)
        case activateDefault
        case ignored
        case beep
        /// Clone TERec AND hText, zero only viewRect, run probeByte through TEKey.
        /// Preserve the original forwarded byte; this matters for27/127.
        case probeHint(probeByte: UInt8, forwardedByte: UInt8)
        /// First copy visible selection into hidden TE. Apply hiddenByte if present,
        /// then send visibleByte to the original dialog's visible TE.
        case maskedKey(visibleByte: UInt8, hiddenByte: UInt8?)
    }

    static func encodedBytes(_ text: String) throws -> [UInt8] {
        guard let data = text.data(using: .macOSRoman, allowLossyConversion: false) else { throw EncodingError.notMacRoman }
        return Array(data)
    }

    /// CODE15:0138–014a clamps COMMITTED length; it does not sanitize pasted bytes.
    /// Empty-new-password and old-password comparison remain separate validation.
    static func committedPassword(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes.prefix(changedPasswordByteLimit))
    }

    /// Only events delivered to the custom filter belong here. System7 can handle
    /// standard Edit commands outside this function. Do not sanitize clipboard
    /// bytes by replaying this function per character.
    static func changeKey(_ byte: UInt8, eventKind: EventKind = .keyDown,
                          field: Field, textByteCount: Int, selection: Range<Int>) -> Action {
        precondition(field != .enablePassword)
        precondition(textByteCount >= 0 && selection.lowerBound >= 0 && selection.upperBound <= textByteCount)
        //017c–01ca: Return/Enter are rewritten BEFORE CODE1's default-button filter.
        if byte == 3 || byte == 13 { return .forwardToDialog(9) }
        //CODE1:0400–0494 handles Tab for both keyDown and autoKey, ignoring Shift.
        if byte == 9 {
            switch field {
            case .oldPassword: return .selectAll(.newPassword)
            case .newPassword: return .selectAll(.hint)
            case .hint: return .selectAll(.oldPassword)
            case .enablePassword: preconditionFailure("Wrong dialog")
            }
        }
        if field == .hint {
            //0316–032a alters D7 only, not event.message.0382 probes cloned TE.
            return .probeHint(probeByte: byte == 27 || byte == 127 ? 8 : byte, forwardedByte: byte)
        }
        //0220–025c whitelist runs BEFORE the unreachable27/127 remap at0260.
        guard passwordByteAllowed(byte) else { return .ignored }
        if byte == 8 { return .forwardToDialog(byte) }
        //0294–02d6 also tests arrows; it is not restricted to printable insertions.
        return textByteCount - selection.count < changedPasswordByteLimit ? .forwardToDialog(byte) : .beep
    }

    /// nil models either HandToHand allocation failure, not an unknown line count.
    /// Callers without an authoritative TextEdit line count must retain probeHint
    /// as unresolved, rather than passing a guessed count or nil.
    static func resolveHintProbe(lineCount: Int?, forwardedByte: UInt8) -> Action {
        guard let lineCount else { return .beep }
        return lineCount <= maximumHintLines ? .forwardToDialog(forwardedByte) : .beep
    }

    static func enableKey(_ byte: UInt8, eventKind: EventKind = .keyDown) -> Action {
        //CODE1:037e–03e4 accepts Return/Enter only on keyDown, not autoKey.
        if eventKind == .keyDown && (byte == 3 || byte == 13) { return .activateDefault }
        if byte == 9 { return .selectAll(.enablePassword) }
        guard passwordByteAllowed(byte) else { return .ignored }
        //1382–13a8 synchronize selection even for arrows.13ba–13d6 skip hidden
        //TEKey for arrows; the next input resynchronizes from the visible selection.
        if (28...31).contains(byte) { return .maskedKey(visibleByte: byte, hiddenByte: nil) }
        return .maskedKey(visibleByte: byte >= 32 ? maskByte : byte, hiddenByte: byte)
    }

    enum DialogAction: Equatable, Sendable {
        case textEditKey(UInt8), cut, copy, paste, ignored
    }

    /// Reference System7 lpch31:1ba36–1bac6 DSEdit, reached only AFTER the app
    /// filter forwards the event. In Enable this must receive maskByte, not the
    /// original letter: Command+bullet is ignored even though hidden TE changed.
    static func systemDialogKey(_ byte: UInt8, virtualKey: UInt8 = 0,
                                command: Bool, hasSelection: Bool) -> DialogAction {
        let operation: UInt8
        if byte == 0x10 {
            switch virtualKey {
            case 0x78: operation = 88
            case 0x63: operation = 67
            case 0x76: operation = 86
            default: return .ignored
            }
        } else if command {
            operation = byte & 0xdf // Original BCLR #5, not Unicode uppercasing.
        } else {
            return .textEditKey(byte)
        }
        switch operation {
        case 67: return hasSelection ? .copy : .ignored
        case 86: return .paste
        case 88: return hasSelection ? .cut : .ignored
        default: return .ignored
        }
    }

    private static func passwordByteAllowed(_ byte: UInt8) -> Bool {
        (33...126).contains(byte) || (8...9).contains(byte) || (28...31).contains(byte)
    }
}
