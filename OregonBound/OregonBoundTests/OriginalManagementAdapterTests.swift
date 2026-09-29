#if os(macOS)
import AppKit
import Testing
@testable import OregonBound

@MainActor @Suite(.enabled(if: GameData.isReady))
struct OriginalManagementAdapterTests {
    private func editor(_ field: OriginalManagementTextEdit.Field = .oldPassword) -> OriginalManagementEditor {
        let editor = OriginalManagementEditor(frame: .zero, textContainer: nil)
        editor.frame = NSRect(x: 0, y: 0, width: 135, height: 48)
        editor.field = field
        editor.beep = {}
        return editor
    }
    private func event(_ text: String, keyCode: UInt16 = 0, command: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: command ? .command : [], timestamp: 0, windowNumber: 0,
            context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: keyCode))
    }
    @Test func realNativeTypingOwnsTextSystemAndUpdatesBinding() throws {
        let view = editor()
        var output = ""
        view.changed = { output = $0 }
        #expect(view.textStorage != nil && view.textContainer != nil && view.layoutManager != nil)
        view.keyDown(with: try event("b"))
        view.insertText("oom", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "boom" && output == "boom")
        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
        view.keyDown(with: try event("\u{7f}", keyCode: 51))
        #expect(view.string == "boo" && output == "boo")
        view.insertText("A", replacementRange: NSRange(location: 0, length: 3))
        #expect(view.string == "A" && output == "A")
        view.keyDown(with: try event(" "))
        view.keyDown(with: try event("\u{f728}", keyCode: 117))
        #expect(view.string == "A")
    }
    @Test func returnCyclesChangeFieldsButEnableRunsDefault() throws {
        let group = OriginalManagementFocusGroup()
        var selected: [OriginalManagementTextEdit.Field] = []
        for field in [OriginalManagementTextEdit.Field.oldPassword, .newPassword, .hint, .enablePassword] {
            group.register(field, select: { _ in selected.append(field) }, selection: { nil })
        }
        let view = editor(); view.focusGroup = group
        var defaults = 0; view.onDefault = { defaults += 1 }
        view.keyDown(with: try event("\r"))
        #expect(selected == [.newPassword] && defaults == 0)
        view.field = .hint; view.routeKey(9)
        #expect(selected.last == .oldPassword)
        view.field = .enablePassword; view.routeKey(13)
        #expect(defaults == 1)
        view.routeKey(13, autoKey: true)
        #expect(defaults == 1)
    }
    @Test func selectionSurvivesDisabledAlertAndBlocksAllMutations() {
        let view = editor(.enablePassword)
        view.synchronize("boom")
        view.setSelectedRange(NSRange(location: 0, length: 4))
        let selected = view.selectedRange()
        var defaults = 0; view.onDefault = { defaults += 1 }
        view.isEditable = false; view.isSelectable = false
        view.routeKey(65); view.routeKey(13); view.paste(nil)
        view.synchronize("boom")
        view.isEditable = true; view.isSelectable = true
        #expect(view.selectedRange() == selected)
        #expect(view.hiddenPassword == "boom" && view.string == "••••" && defaults == 0)
        view.routeKey(65)
        #expect(view.hiddenPassword == "A" && view.string == "•")
    }
    @Test func enabledHiddenClipboardDivergenceSurvivesBindingSynchronization() {
        let view = editor(.enablePassword)
        var reads = 0
        view.readClipboard = { reads += 1; return "SHOULD NOT PASTE" }
        view.synchronize(""); view.routeKey(98)
        view.routeKey(118, command: true)
        #expect(view.hiddenPassword == "bv" && view.string == "•" && reads == 0)
        view.synchronize(view.actualText)
        #expect(view.string == "•")
        view.routeKey(111)
        #expect(view.hiddenPassword == "bov" && view.string == "••")
    }
    @Test func pasteUsesWholeScrapAfterOneKeyFilterAndPreservesMacRoman() {
        let view = editor()
        view.synchronize("123456789"); view.setSelectedRange(NSRange(location: 9, length: 0))
        view.readClipboard = { "é \rMORE" }
        view.paste(nil)
        #expect(view.string == "123456789é \rMORE")
        let before = view.string
        view.paste(nil)
        #expect(view.string == before)
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.readClipboard = { "🙂" }
        view.paste(nil)
        #expect(view.string == before)
    }
    @Test func hintChecksOriginalLinesButPasteCanExceedThree() throws {
        let view = editor(.hint)
        #if SWIFT_PACKAGE
        view.bitmapFont = try #require(BitmapFont(resource: 5478, bundle: .module))
        #else
        view.bitmapFont = try #require(BitmapFont.chicago12)
        #endif
        let full = String(repeating: "W", count: 33)
        view.synchronize(full); view.setSelectedRange(NSRange(location: 33, length: 0))
        var beeps = 0; view.beep = { beeps += 1 }
        view.routeKey(87)
        #expect(view.string == full && beeps == 1)
        view.setSelectedRange(NSRange(location: 0, length: 33))
        view.readClipboard = { String(repeating: "W", count: 80) }
        view.paste(nil)
        #expect(view.string.count == 80) // The probe inserted V into the selected clone.
        view.synchronize("a"); view.setSelectedRange(NSRange(location: 1, length: 0))
        view.routeKey(27) // Probe backspace; actual TEKey inserts Escape.
        #expect(Array(try #require(view.string.data(using: .macOSRoman))) == [97,27])
    }
    @Test func unfocusedKeyEquivalentCannotConsumeCommands() throws {
        let view = editor()
        #expect(view.performKeyEquivalent(with: try event("v", command: true)) == false)
        #expect(OriginalManagementEditor.originalKeyByte("\u{7f}", keyCode: 51) == 8)
        #expect(OriginalManagementEditor.originalKeyByte("\u{f728}", keyCode: 117) == 127)
    }
    @Test func focusGroupExposesSourceSelectionForAlerts() {
        let group = OriginalManagementFocusGroup()
        var current = 0..<0
        group.register(.enablePassword, select: { current = $0 ?? 0..<4 }, selection: { current })
        group.select(.enablePassword, range: 0..<2000)
        #expect(group.selection(in: .enablePassword) == 0..<2000)
        group.selectAll(.enablePassword)
        #expect(current == 0..<4)
    }
    @Test func compatibilityPreservesUnicodeHintAndNativeInk() {
        let view = editor(.hint); view.legacyCompatibility = true
        let original = "Keep 🙂 and e\u{301} exactly"
        view.synchronize(original)
        #expect(view.string == original && view.actualText == original)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        var output = ""; view.changed = { output = $0 }
        view.insertText(" 🦋", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == original + " 🦋" && output == original + " 🦋")
        #expect(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .black)
    }
    @Test func compatibilityCanEnterUnicodePasswordAndDeleteWholeCharacter() {
        let view = editor(.enablePassword); view.legacyCompatibility = true
        view.synchronize("")
        var output = ""; view.changed = { output = $0 }
        view.insertText("🔐密碼", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.actualText == "🔐密碼" && output == "🔐密碼")
        #expect(view.string == "••••")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.deleteBackward(nil)
        #expect(view.actualText == "密碼" && view.string == "••")
        view.isEditable = false
        view.insertText("NO", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.actualText == "密碼")
        view.isEditable = true; view.synchronize("🔐")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText("A", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.actualText == "🔐A") // A bullet caret cannot split a Unicode surrogate.
    }
    @Test func decomposedMacRomanHintCanonicalizesBeforeByteSelection() throws {
        let view = editor(.hint)
        #if SWIFT_PACKAGE
        view.bitmapFont = try #require(BitmapFont(resource: 5478, bundle: .module))
        #else
        view.bitmapFont = try #require(BitmapFont.chicago12)
        #endif
        view.synchronize("e\u{301}")
        #expect(view.string.utf16.count == 1)
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.routeKey(65)
        #expect(view.string == "A")
    }

}
#endif
