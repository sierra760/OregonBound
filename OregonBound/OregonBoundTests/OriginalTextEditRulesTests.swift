import Testing
@testable import OregonBound

struct OriginalTextEditRulesTests {
    private let narrow: ([UInt8]) -> Int = { $0.count * 4 }
    private let wide: ([UInt8]) -> Int = { $0.count * 12 }

    @Test func capStartsZeroAndIsSharedAcrossFields() {
        var state = OriginalTextEditRules.State()
        #expect(state.key(9, text: [], selection: 0..<0, width: narrow) == .nextField)
        #expect(state.byteLimit == 0)
        #expect(state.key(118, command: true, text: [], selection: 0..<0, clipboard: [65], width: narrow) == .beep)
        #expect(state.key(8, text: [], selection: 0..<0, width: narrow) == .textEditKey(8))
        #expect(state.byteLimit == 10)
        #expect(state.key(118, command: true, text: [], selection: 0..<0, clipboard: [65], width: narrow) == .insert([65]))
        #expect(state.key(65, text: Array(repeating: 65, count: 10), selection: 10..<10, width: narrow) == .beep)
        // Longer authored default names are not truncated by installing a field.
        #expect(state.key(65, text: Array(repeating: 65, count: 13), selection: 0..<5, width: narrow) == .insert([65]))
    }
    @Test func pixelWidthSubtractsSelectedRunAndAllowsEquality() {
        var state = OriginalTextEditRules.State()
        let width: ([UInt8]) -> Int = { $0.reduce(0) { $0 + Int($1) } }
        #expect(state.key(65, text: [52], selection: 1..<1, width: width) == .insert([65])) //117
        #expect(state.key(65, text: [53], selection: 1..<1, width: width) == .beep) //118
        #expect(state.key(65, text: [53], selection: 0..<1, width: width) == .insert([65]))
    }
    @Test func menuPasteBypassesWidthAndPastedControlBytesAreNotKeys() {
        var state = OriginalTextEditRules.State()
        _ = state.key(8, text: [], selection: 0..<0, width: narrow)
        let text = Array(repeating: UInt8(65), count: 9)
        #expect(state.paste([65], text: text, selection: 9..<9, fromMenu: false, width: wide) == .beep)
        #expect(state.menu(.paste, text: text, selection: 9..<9, clipboard: [65], width: wide) == .insert([65]))
        #expect(state.paste([13, 9, 27], text: [], selection: 0..<0, fromMenu: false, width: narrow) == .insert([13, 9, 27]))
        #expect(state.menu(.clear, text: text, selection: 3..<4, width: wide) == .clearAll)
    }
    @Test func keyRoutingUsesOriginalByteCodes() {
        var state = OriginalTextEditRules.State()
        for byte in [UInt8(27), 127, 8] {
            #expect(state.key(byte, text: [], selection: 0..<0, width: narrow) == .textEditKey(8))
        }
        for byte in [UInt8(3), 13, 31, 9] {
            #expect(state.key(byte, text: [], selection: 0..<0, width: narrow) == .nextField)
        }
        #expect(state.key(30, text: [], selection: 0..<0, width: narrow) == .previousField)
        for byte in [UInt8(28), 29] {
            #expect(state.key(byte, text: [], selection: 0..<0, width: narrow) == .textEditKey(byte))
        }
        for byte in UInt8(32)...UInt8(255) where byte != 127 {
            #expect(state.key(byte, text: [], selection: 0..<0, width: narrow) == .insert([byte]))
        }
        #expect(state.key(0, text: [], selection: 0..<0, width: narrow) == .ignored)
        #expect(state.key(97, command: true, text: [], selection: 0..<0, width: narrow) == .unhandled)
        #expect(state.key(46, command: true, text: [], selection: 0..<0, width: narrow) == .ignored)
        #expect(state.key(120, command: true, text: [], selection: 0..<0, width: narrow) == .cut)
    }
}
