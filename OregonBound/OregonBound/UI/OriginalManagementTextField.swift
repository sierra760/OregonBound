import SwiftUI

@MainActor final class OriginalManagementFocusGroup: ObservableObject {
    typealias Field = OriginalManagementTextEdit.Field
    private struct Entry {
        let field: Field
        let select: (Range<Int>?) -> Void
        let selection: () -> Range<Int>?
    }
    private var entries: [Entry] = []
    func register(_ field: Field, select: @escaping (Range<Int>?) -> Void,
                  selection: @escaping () -> Range<Int>?) {
        entries.removeAll { $0.field == field }
        entries.append(.init(field: field, select: select, selection: selection))
    }
    func selectAll(_ field: Field) { entries.first { $0.field == field }?.select(nil) }
    func select(_ field: Field, range: Range<Int>) { entries.first { $0.field == field }?.select(range) }
    func selection(in field: Field) -> Range<Int>? { entries.first { $0.field == field }?.selection() }
    func moveNext(from field: Field) {
        switch field {
        case .oldPassword: selectAll(.newPassword)
        case .newPassword: selectAll(.hint)
        case .hint: selectAll(.oldPassword)
        case .enablePassword: selectAll(.enablePassword)
        }
    }
}

/// Enable's binding contains the hidden actual password, not the visible bullets.
/// macOS preserves original key/filter/clipboard order and bitmap line placement.
/// iOS currently provides the explicitly documented native compatibility editor.
struct OriginalManagementTextField: View {
    let label: String
    @Binding var text: String
    let field: OriginalManagementTextEdit.Field
    let focusGroup: OriginalManagementFocusGroup
    var legacyCompatibility = false
    var initialFocus = false
    var onDefault: () -> Void = {}
    @Environment(\.isEnabled) private var enabled
    @State private var displayedText = ""
    var body: some View {
        #if os(macOS)
        ZStack(alignment: .topLeading) {
            OriginalManagementNativeField(text: $text, displayedText: $displayedText,
                label: label, field: field, focusGroup: focusGroup, legacyCompatibility: legacyCompatibility, initialFocus: initialFocus,
                enabled: enabled, onDefault: onDefault)
            if !legacyCompatibility {
                OriginalManagementBitmapInk(text: displayedText, width: field == .enablePassword ? 132 : 135)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.clipped()
        #else
        OriginalManagementFallbackField(label: label, text: $text, field: field,
            focusGroup: focusGroup, initialFocus: initialFocus, onDefault: onDefault)
        #endif
    }
}

private struct OriginalManagementBitmapInk: View {
    let text: String
    let width: Int
    var body: some View {
        if let font = BitmapFont.chicago12,
           let bytes = try? OriginalManagementTextEdit.encodedBytes(text),
           let widths = font.prefixWidths(text),
           let lines = try? OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: widths, width: width) {
            Canvas { context, _ in
                for row in 0..<lines.lineCount {
                    let start = lines.lineStarts[row], end = lines.lineStarts[row + 1]
                    for index in start..<end where bytes[index] != 13 {
                        // LF is a missing Chicago glyph, not a second newline convention.
                        let character = bytes[index] == 10 ? "\u{fffd}" : String(data: Data([bytes[index]]), encoding: .macOSRoman)!
                        for glyph in font.layout(character).glyphs {
                            let rect = glyph.rect.offsetBy(dx: CGFloat(widths[index] - widths[start]),
                                                           dy: CGFloat(row * font.lineHeight))
                            context.draw(Image(decorative: glyph.image, scale: 1).interpolation(.none), in: rect)
                        }
                    }
                }
            }
        }
    }
}

#if os(macOS)
import AppKit

private struct OriginalManagementNativeField: NSViewRepresentable {
    @Binding var text: String
    @Binding var displayedText: String
    let label: String
    let field: OriginalManagementTextEdit.Field
    let focusGroup: OriginalManagementFocusGroup
    let legacyCompatibility: Bool
    let initialFocus: Bool
    let enabled: Bool
    let onDefault: () -> Void
    func makeNSView(context: Context) -> OriginalManagementEditor {
        let editor = OriginalManagementEditor(frame: .zero, textContainer: nil)
        updateNSView(editor, context: context)
        return editor
    }
    func updateNSView(_ editor: OriginalManagementEditor, context: Context) {
        editor.field = field; editor.focusGroup = focusGroup
        editor.legacyCompatibility = legacyCompatibility
        editor.initialFocus = initialFocus; editor.onDefault = onDefault
        editor.isEditable = enabled; editor.isSelectable = enabled
        editor.setAccessibilityLabel(label)
        editor.changed = { text = $0 }
        editor.displayChanged = { displayedText = $0 }
        editor.synchronize(text)
        focusGroup.register(field, select: { [weak editor] range in
            guard let editor, editor.isEditable else { return }
            editor.window?.makeFirstResponder(editor)
            let count = editor.string.utf16.count
            let start = min(count, max(0, range?.lowerBound ?? 0))
            let end = min(count, max(start, range?.upperBound ?? count))
            editor.setSelectedRange(NSRange(location: start, length: end - start))
        }, selection: { [weak editor] in editor?.byteSelection })
        editor.applyInitialFocusIfNeeded()
    }
}

@MainActor final class OriginalManagementEditor: NSTextView {
    typealias Rules = OriginalManagementTextEdit
    var field: Rules.Field = .oldPassword
    var legacyCompatibility = false {
        didSet { if oldValue != legacyCompatibility { loadedBinding = false; applyOriginalAdvances() } }
    }
    weak var focusGroup: OriginalManagementFocusGroup?
    var initialFocus = false
    var onDefault: () -> Void = {}
    var changed: (String) -> Void = { _ in }
    var displayChanged: (String) -> Void = { _ in }
    var beep: () -> Void = { NSSound.beep() }
    var readClipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    var writeClipboard: (String) -> Void = { value in
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
    var bitmapFont: BitmapFont? = .chicago12
    private(set) var hiddenPassword = ""
    private var loadedBinding = false
    private var appliedInitialFocus = false
    private var ownedStorage: NSTextStorage?
    private let metricFont = NSFont.systemFont(ofSize: 12)
    var actualText: String { field == .enablePassword ? hiddenPassword : string }
    var byteSelection: Range<Int> {
        let count = string.utf16.count, range = selectedRange()
        let start = min(count, range.location)
        return start..<min(count, start + range.length)
    }
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let storage = container == nil ? NSTextStorage() : nil
        let resolved = container ?? NSTextContainer(size: NSSize(width: max(1, frameRect.width), height: .greatestFiniteMagnitude))
        if let storage {
            let layout = NSLayoutManager(); storage.addLayoutManager(layout); layout.addTextContainer(resolved)
        }
        super.init(frame: frameRect, textContainer: resolved)
        ownedStorage = storage
        resolved.widthTracksTextView = true; resolved.heightTracksTextView = false
        resolved.lineFragmentPadding = 0
        isRichText = false; allowsUndo = false; importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false; isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false; isAutomaticSpellingCorrectionEnabled = false
        drawsBackground = false; textContainerInset = .zero; insertionPointColor = .black
        isVerticallyResizable = false; isHorizontallyResizable = false
        applyOriginalAdvances()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyInitialFocusIfNeeded() }
    func applyInitialFocusIfNeeded() {
        guard isEditable, initialFocus, !appliedInitialFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditable, !self.appliedInitialFocus, self.window != nil else { return }
            self.appliedInitialFocus = true
            self.window?.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: 0, length: self.string.utf16.count))
        }
    }
    func synchronize(_ value: String) {
        let stored: String
        if legacyCompatibility { stored = value }
        else {
            guard let bytes = try? Rules.encodedBytes(value) else { return }
            // Foundation may encode decomposed Unicode as one Mac Roman byte.
            // Store its round trip so NSTextView UTF16 indices equal source bytes.
            stored = String(data: Data(bytes), encoding: .macOSRoman)!
        }
        guard !loadedBinding || actualText != stored else { return }
        loadedBinding = true
        if field == .enablePassword {
            hiddenPassword = stored
            string = String(repeating: "•", count: stored.utf16.count)
        } else { string = stored }
        setSelectedRange(NSRange(location: min(selectedRange().location, string.utf16.count), length: 0))
        applyOriginalAdvances()
        // Defer SwiftUI state synchronization until after updateNSView.
        let displayed = string
        DispatchQueue.main.async { [weak self] in
            guard let self, self.string == displayed else { return }
            self.displayChanged(displayed)
        }
    }
    static func originalKeyByte(_ characters: String, keyCode: UInt16? = nil) -> UInt8? {
        if keyCode == 51 { return 8 } // Modern Backspace reports127; classic key0x33 emits8.
        switch characters {
        case "\u{f700}": return 30
        case "\u{f701}": return 31
        case "\u{f702}": return 28
        case "\u{f703}": return 29
        case "\u{f728}": return 127
        default:
            guard let bytes = try? Rules.encodedBytes(characters), bytes.count == 1 else { return nil }
            return bytes[0]
        }
    }
    override func keyDown(with event: NSEvent) {
        guard isEditable else { return }
        if legacyCompatibility {
            if let characters = event.characters, let byte = Self.originalKeyByte(characters, keyCode: event.keyCode),
               byte == 3 || byte == 13 || byte == 9 {
                if byte == 9 || field != .enablePassword { focusGroup?.moveNext(from: field) }
                else if !event.isARepeat { onDefault() }
            } else { super.keyDown(with: event) }
            return
        }
        guard let characters = event.characters, let key = Self.originalKeyByte(characters, keyCode: event.keyCode) else {
            super.keyDown(with: event); return
        }
        routeKey(key, command: event.modifierFlags.contains(.command), autoKey: event.isARepeat)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable, window?.firstResponder === self, event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers, let key = Self.originalKeyByte(characters, keyCode: event.keyCode) else { return false }
        if legacyCompatibility {
            switch key & 0xdf {
            case 67: copy(nil)
            case 86: paste(nil)
            case 88: cut(nil)
            case 65: selectAll(nil)
            default: return false
            }
            return true
        }
        routeKey(key, command: true, autoKey: event.isARepeat)
        return true
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        let value = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
        if legacyCompatibility {
            let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            replaceLegacySelection(with: value, range: range)
            return
        }
        guard let bytes = try? Rules.encodedBytes(value) else { beep(); return }
        if replacementRange.location != NSNotFound {
            guard replacementRange.location + replacementRange.length <= string.utf16.count else { beep(); return }
            setSelectedRange(replacementRange)
        }
        for byte in bytes { routeKey(byte) }
    }
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if legacyCompatibility {
            guard let value = readClipboard() else { return }
            replaceLegacySelection(with: value, range: selectedRange())
        } else { routeKey(118, command: true) }
    }
    override func copy(_ sender: Any?) {
        guard isEditable else { return }
        if legacyCompatibility {
            if selectedRange().length > 0 { writeClipboard((string as NSString).substring(with: selectedRange())) }
        } else { routeKey(99, command: true) }
    }
    override func cut(_ sender: Any?) {
        guard isEditable else { return }
        if legacyCompatibility {
            copy(sender)
            if selectedRange().length > 0 { replaceLegacySelection(with: "", range: selectedRange()) }
        } else { routeKey(120, command: true) }
    }
    override func delete(_ sender: Any?) {
        guard isEditable, legacyCompatibility, selectedRange().length > 0 else { return }
        replaceLegacySelection(with: "", range: selectedRange())
    }
    override func selectAll(_ sender: Any?) {
        guard isEditable else { return }
        if legacyCompatibility { setSelectedRange(NSRange(location: 0, length: string.utf16.count)) }
        else { routeKey(97, command: true) }
    }
    override func deleteBackward(_ sender: Any?) {
        guard isEditable else { return }
        if !legacyCompatibility { routeKey(8); return }
        var range = selectedRange()
        if range.length == 0 {
            guard range.location > 0 else { return }
            range = (actualText as NSString).rangeOfComposedCharacterSequence(at: range.location - 1)
        }
        replaceLegacySelection(with: "", range: range)
    }
    override func deleteForward(_ sender: Any?) {
        guard isEditable else { return }
        if !legacyCompatibility { routeKey(127); return }
        var range = selectedRange()
        if range.length == 0 {
            guard range.location < actualText.utf16.count else { return }
            range = (actualText as NSString).rangeOfComposedCharacterSequence(at: range.location)
        }
        replaceLegacySelection(with: "", range: range)
    }
    private func replaceLegacySelection(with replacement: String, range: NSRange) {
        guard isEditable, range.location != NSNotFound else { return }
        let source = actualText as NSString
        guard range.location <= source.length, range.length <= source.length - range.location else { beep(); return }
        // Native compatibility uses Unicode character boundaries, never splits a surrogate.
        var normalized = range.length > 0 ? source.rangeOfComposedCharacterSequences(for: range) : range
        if normalized.length == 0 && normalized.location < source.length {
            let character = source.rangeOfComposedCharacterSequence(at: normalized.location)
            if normalized.location > character.location {
                normalized.location = character.location + character.length
            }
        }
        let result = source.replacingCharacters(in: normalized, with: replacement)
        if field == .enablePassword {
            hiddenPassword = result
            string = String(repeating: "•", count: result.utf16.count)
        } else { string = result }
        setSelectedRange(NSRange(location: normalized.location + replacement.utf16.count, length: 0))
        didChangeText()
    }

    func routeKey(_ byte: UInt8, command: Bool = false, autoKey: Bool = false) {
        guard isEditable else { return }
        if legacyCompatibility {
            if byte == 8 { deleteBackward(nil) }
            else if byte == 9 || byte == 3 || byte == 13 {
                if field == .enablePassword && byte != 9 { if !autoKey { onDefault() } }
                else { focusGroup?.moveNext(from: field) }
            } else if !command {
                replaceLegacySelection(with: String(data: Data([byte]), encoding: .macOSRoman)!, range: selectedRange())
            }
            return
        }
        guard let bytes = try? Rules.encodedBytes(string) else { return }
        let action = field == .enablePassword
            ? Rules.enableKey(byte, eventKind: autoKey ? .autoKey : .keyDown)
            : Rules.changeKey(byte, eventKind: autoKey ? .autoKey : .keyDown,
                field: field, textByteCount: bytes.count, selection: byteSelection)
        perform(action, command: command)
    }
    private func perform(_ action: Rules.Action, command: Bool) {
        switch action {
        case .forwardToDialog(9): focusGroup?.moveNext(from: field)
        case .forwardToDialog(let byte): dispatchVisible(byte, command: command)
        case .selectAll(let field): focusGroup?.selectAll(field)
        case .activateDefault: onDefault()
        case .ignored: break
        case .beep: beep()
        case .probeHint(let probe, let forwarded):
            guard let candidate = probedText(key: probe), let font = bitmapFont,
                  let bytes = try? Rules.encodedBytes(candidate), let widths = font.prefixWidths(candidate),
                  let lines = try? OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: widths, width: Rules.hintWidth) else {
                beep(); return // Unsupported input/metrics; never assume the probe passed.
            }
            perform(Rules.resolveHintProbe(lineCount: lines.lineCount, forwardedByte: forwarded), command: command)
        case .maskedKey(let visible, let hidden):
            if let hidden {
                // TESetSelect clamps the visible selection to the hidden record length.
                let count = hiddenPassword.utf16.count
                let start = min(count, byteSelection.lowerBound), end = min(count, byteSelection.upperBound)
                guard let result = Self.editedText(hiddenPassword, selection: start..<end, key: hidden) else { beep(); return }
                hiddenPassword = result.text
            }
            dispatchVisible(visible, command: command)
            changed(actualText) // Hidden-only Command edits do not invoke didChangeText.
        }
    }
    private func dispatchVisible(_ byte: UInt8, command: Bool) {
        switch Rules.systemDialogKey(byte, command: command, hasSelection: !byteSelection.isEmpty) {
        case .textEditKey(let key):
            switch key {
            case 28: super.moveLeft(nil)
            case 29: super.moveRight(nil)
            case 30: super.moveUp(nil)
            case 31: super.moveDown(nil)
            default:
                guard let result = Self.editedText(string, selection: byteSelection, key: key) else { beep(); return }
                replaceVisible(result.text, caret: result.caret)
            }
        case .copy:
            writeClipboard((string as NSString).substring(with: selectedRange()))
        case .cut:
            writeClipboard((string as NSString).substring(with: selectedRange()))
            guard let result = Self.editedText(string, selection: byteSelection, key: 8) else { return }
            replaceVisible(result.text, caret: result.caret)
        case .paste:
            guard let clipboard = readClipboard(), let inserted = try? Rules.encodedBytes(clipboard),
                  var bytes = try? Rules.encodedBytes(string),
                  bytes.count - byteSelection.count + inserted.count <= 32767 else { beep(); return }
            let caret = byteSelection.lowerBound + inserted.count
            bytes.replaceSubrange(byteSelection, with: inserted)
            replaceVisible(String(data: Data(bytes), encoding: .macOSRoman)!, caret: caret)
        case .ignored: break
        }
    }
    private func probedText(key: UInt8) -> String? {
        // Arrow keys change selection only, so the cloned nLines is unchanged.
        if (28...31).contains(key) { return string }
        return Self.editedText(string, selection: byteSelection, key: key)?.text
    }
    struct EditResult { let text: String; let caret: Int }
    static func editedText(_ text: String, selection: Range<Int>, key: UInt8) -> EditResult? {
        guard var bytes = try? Rules.encodedBytes(text), selection.lowerBound >= 0, selection.upperBound <= bytes.count else { return nil }
        var selected = selection
        if key == 8 {
            if selected.isEmpty && selected.lowerBound > 0 { selected = (selected.lowerBound - 1)..<selected.upperBound }
            bytes.removeSubrange(selected)
            return .init(text: String(data: Data(bytes), encoding: .macOSRoman)!, caret: selected.lowerBound)
        }
        guard bytes.count - selected.count < 32767 else { return nil }
        bytes.replaceSubrange(selected, with: [key])
        return .init(text: String(data: Data(bytes), encoding: .macOSRoman)!, caret: selected.lowerBound + 1)
    }
    private func replaceVisible(_ text: String, caret: Int) {
        string = text
        setSelectedRange(NSRange(location: caret, length: 0))
        didChangeText()
    }
    override func didChangeText() {
        super.didChangeText(); applyOriginalAdvances()
        displayChanged(string); changed(actualText)
    }
    func applyOriginalAdvances() {
        guard let storage = textStorage else { return }
        if legacyCompatibility {
            let attributes: [NSAttributedString.Key: Any] = [.font: metricFont, .foregroundColor: NSColor.black]
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            typingAttributes = attributes
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 16; paragraph.maximumLineHeight = 16
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: metricFont, .foregroundColor: NSColor.clear,
            .ligature: 0, .paragraphStyle: paragraph]
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        for index in 0..<storage.length {
            let range = NSRange(location: index, length: 1)
            let character = (string as NSString).substring(with: range)
            let native = (character as NSString).size(withAttributes: [.font: metricFont]).width
            let target = CGFloat(bitmapFont?.width(character) ?? Int(native))
            storage.addAttribute(.kern, value: target - native, range: range)
        }
        typingAttributes = attributes
    }
}
#else
private struct OriginalManagementFallbackField: View {
    let label: String
    @Binding var text: String
    let field: OriginalManagementTextEdit.Field
    let focusGroup: OriginalManagementFocusGroup
    let initialFocus: Bool
    let onDefault: () -> Void
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if field == .enablePassword { SecureField(label, text: $text).onSubmit(onDefault) }
            else if field == .hint { TextEditor(text: $text) }
            else { TextField(label, text: $text).onSubmit { focusGroup.moveNext(from: field) } }
        }
        .textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
        .autocorrectionDisabled().textInputAutocapitalization(.never)
        .onAppear {
            focusGroup.register(field, select: { _ in if enabled { focused = true } }, selection: { nil })
            if initialFocus && enabled { focused = true }
        }
        .onChange(of: enabled) { if !$0 { focused = false } }
    }
}
#endif
