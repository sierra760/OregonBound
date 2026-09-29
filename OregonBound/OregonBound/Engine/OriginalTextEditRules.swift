/// Single-wagon registration's CODE5 TextEdit filter and CODE19 setup.
/// Input/selection indices are MacRoman BYTES. Caret geometry and TEKey's
/// selection semantics remain the platform adapter's responsibility.
enum OriginalTextEditRules {
    static let registrationFontResource = 16131 // WTTimes6322, bold,14
    static let registrationWidth = 117
    enum Action: Equatable {
        case insert([UInt8]), textEditKey(UInt8)
        case nextField, previousField, copy, cut, clearAll
        case ignored, unhandled, beep
    }
    enum EditMenuItem { case undo, cut, copy, paste, clear }
    struct State {
        /// CODE19:099c resets this to0. The first non-command key sets10.
        /// Preserve this across all five fields, as the original global does.
        private(set) var byteLimit = 0

        mutating func key(_ byte: UInt8, command: Bool = false,
                          text: [UInt8], selection: Range<Int>, clipboard: [UInt8] = [],
                          width: ([UInt8]) -> Int) -> Action {
            // Pane handler CODE5:39dc intercepts Tab before text filtering.
            if byte == 9 { return .nextField }
            if command {
                let upper = (97...122).contains(byte) ? byte - 32 : byte
                switch upper {
                case 88: return .cut
                case 67: return .copy
                case 86: return paste(clipboard, text: text, selection: selection, fromMenu: false, width: width)
                case 46: return .ignored // registration has no cancel item
                default: return .unhandled
                }
            }
            if byteLimit < 1 { byteLimit = 10 }
            let key = (byte == 27 || byte == 127) ? UInt8(8) : byte
            switch key {
            case 3, 13, 31: return .nextField
            case 30: return .previousField
            case 8, 28, 29: return .textEditKey(key)
            case 32...255:
                let selected = selectedBytes(text, selection)
                guard text.count - selected.count < byteLimit else { return .beep }
                guard width(text) + width([key]) - width(selected) <= OriginalTextEditRules.registrationWidth else { return .beep }
                return .insert([key])
            default: return .ignored
            }
        }

        func paste(_ clipboard: [UInt8], text: [UInt8], selection: Range<Int>,
                   fromMenu: Bool, width: ([UInt8]) -> Int) -> Action {
            let selected = selectedBytes(text, selection)
            guard text.count + clipboard.count - selected.count <= byteLimit else { return .beep }
            // CODE5:19a0 Edit-menu Paste omits the keyboard path's width test.
            if !fromMenu && width(text) + width(clipboard) - width(selected) > OriginalTextEditRules.registrationWidth {
                return .beep
            }
            // Paste calls TEPaste directly: do not run pasted bytes through key().
            return .insert(clipboard)
        }

        func menu(_ item: EditMenuItem, text: [UInt8], selection: Range<Int>,
                  clipboard: [UInt8] = [], width: ([UInt8]) -> Int) -> Action {
            switch item {
            case .undo: return .ignored // item1 has no branch in CODE5:1924
            case .cut: return .cut
            case .copy: return .copy
            case .clear: return .clearAll // explicitly TESetSelect(0,32767), TEDelete
            case .paste: return paste(clipboard, text: text, selection: selection, fromMenu: true, width: width)
            }
        }

        private func selectedBytes(_ text: [UInt8], _ range: Range<Int>) -> [UInt8] {
            let lower = min(text.count, max(0, range.lowerBound))
            let upper = min(text.count, max(lower, range.upperBound))
            return Array(text[lower..<upper])
        }
    }
}
