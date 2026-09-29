#if os(macOS)
import AppKit
import Testing
@testable import OregonBound

@MainActor struct OriginalRegistrationAdapterTests {
    @Test func printableTypingAndInputServicesUpdateStorageAndBinding() throws {
        // Match NSViewRepresentable construction: zero frame, then layout resize.
        let editor = OriginalRegistrationEditor(frame: .zero, textContainer: nil)
        editor.frame = NSRect(x: 0, y: 0, width: 119, height: 15)
        var rules = OriginalTextEditRules.State()
        var changes: [String] = []
        editor.readRules = { rules }; editor.writeRules = { rules = $0 }
        editor.changed = { changes.append($0) }
        #expect(editor.textStorage != nil && editor.textContainer != nil)
        for character in ["F", "i", "d"] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: 3))
            editor.keyDown(with: event)
        }
        #expect(editor.string == "Fid")
        #expect(changes.last == "Fid")
        editor.insertText("elity", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "Fidelity")
        #expect(changes.last == "Fidelity")
        editor.setSelectedRange(NSRange(location: 0, length: 8))
        editor.insertText("Ada", replacementRange: editor.selectedRange())
        #expect(editor.string == "Ada")
        #expect(changes.last == "Ada")
        #expect(editor.selectedRange() == NSRange(location: 3, length: 0))
    }
    @Test func nativeFunctionKeysMapToClassicTextEditBytes() {
        for (character, byte) in [("\u{f700}", UInt8(30)), ("\u{f701}", 31), ("\u{f702}", 28), ("\u{f703}", 29), ("\u{f728}", 127)] {
            #expect(OriginalRegistrationEditor.originalKeyByte(character) == byte)
        }
        #expect(OriginalRegistrationEditor.originalKeyByte("é") == 0x8e)
        #expect(OriginalRegistrationEditor.originalKeyByte("🛞") == nil)
    }
    @Test func fieldNavigationWrapsOnlyWithinRegisteredNameFields() {
        let group = OriginalRegistrationFocusGroup()
        var focused: [Int] = []
        for index in 0..<5 { group.register(index) { focused.append(index) } }
        group.move(from: 4, direction: 1)
        group.move(from: 0, direction: -1)
        group.move(from: 1, direction: 1)
        #expect(focused == [0, 4, 2])
    }
    @Test func downArrowNavigatesFieldsAndInitializesSharedLimit() throws {
        let group = OriginalRegistrationFocusGroup()
        var focused = -1
        group.register(0) { focused = 0 }
        let editor = OriginalRegistrationEditor(frame: NSRect(x: 0, y: 0, width: 119, height: 15), textContainer: nil)
        var rules = OriginalTextEditRules.State()
        editor.readRules = { rules }; editor.writeRules = { rules = $0 }
        editor.focusGroup = group; editor.fieldIndex = 4
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125))
        editor.keyDown(with: event)
        #expect(focused == 0 && rules.byteLimit == 10)
    }
    @Test func unfocusedEditorDoesNotConsumeClipboardKeyEquivalent() throws {
        let editor = OriginalRegistrationEditor(frame: NSRect(x: 0, y: 0, width: 119, height: 15), textContainer: nil)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        #expect(editor.performKeyEquivalent(with: event) == false)
    }
}
#endif
