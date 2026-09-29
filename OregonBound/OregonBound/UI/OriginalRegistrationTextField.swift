import SwiftUI

/// Original navigation visits only the five editText items and selects all.
@MainActor final class OriginalRegistrationFocusGroup: ObservableObject {
    private var focusActions: [Int: () -> Void] = [:]
    func register(_ index: Int, focus: @escaping () -> Void) { focusActions[index] = focus }
    func move(from index: Int, direction: Int) { focusActions[(index + direction + 5) % 5]?() }
}

/// The five registration fields share CODE5's editor limits. Native TextEdit
/// supplies selection and input services; displayed ink uses the original font.
struct OriginalRegistrationTextField: View {
    let label: String
    @Binding var text: String
    @Binding var rules: OriginalTextEditRules.State
    let focusGroup: OriginalRegistrationFocusGroup
    let fieldIndex: Int
    var initialFocus = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(macOS)
        ZStack(alignment: .topLeading) {
            OriginalRegistrationNativeField(text: $text, rules: $rules, label: label,
                initialFocus: initialFocus, enabled: isEnabled, focusGroup: focusGroup, fieldIndex: fieldIndex)
            OriginalText(text: text, font: .bold14).allowsHitTesting(false).accessibilityHidden(true)
        }.clipped()
        #else
        ZStack(alignment: .topLeading) {
            OriginalRegistrationTouchField(text: $text, rules: $rules, label: label,
                initialFocus: initialFocus, enabled: isEnabled, focusGroup: focusGroup, fieldIndex: fieldIndex)
            OriginalText(text: text, font: .bold14).allowsHitTesting(false).accessibilityHidden(true)
        }.clipped()
        #endif
    }
}

#if os(macOS)
import AppKit

private struct OriginalRegistrationNativeField: NSViewRepresentable {
    @Binding var text: String
    @Binding var rules: OriginalTextEditRules.State
    let label: String
    let initialFocus: Bool
    let enabled: Bool
    let focusGroup: OriginalRegistrationFocusGroup
    let fieldIndex: Int

    func makeNSView(context: Context) -> OriginalRegistrationEditor {
        let view = OriginalRegistrationEditor(frame: .zero, textContainer: nil)
        view.initialFocus = initialFocus
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: OriginalRegistrationEditor, context: Context) {
        view.focusGroup = focusGroup; view.fieldIndex = fieldIndex
        focusGroup.register(fieldIndex) { [weak view] in
            guard let view, view.isEditable else { return }
            view.window?.makeFirstResponder(view)
            view.selectAll(nil)
        }
        view.readRules = { rules }
        view.writeRules = { rules = $0 }
        view.changed = { text = $0 }
        view.isEditable = enabled; view.isSelectable = enabled
        view.setAccessibilityLabel(label)
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        view.applyOriginalAdvances()
        view.applyInitialFocusIfNeeded()
    }
}

final class OriginalRegistrationEditor: NSTextView {
    var initialFocus = false
    weak var focusGroup: OriginalRegistrationFocusGroup?
    var fieldIndex = 0
    var readRules: () -> OriginalTextEditRules.State = { .init() }
    var writeRules: (OriginalTextEditRules.State) -> Void = { _ in }
    var changed: (String) -> Void = { _ in }
    private var appliedInitialFocus = false
    private var applyingOriginalAction = false
    private var ownedTextStorage: NSTextStorage?
    private let metricFont = NSFont(name: "Times-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        // NSTextView's designated initializer does NOT create a text system
        // when passed nil. Navigation works without one, but insertion silently
        // leaves string empty. Own the complete TextKit1 stack for these fields.
        let storage: NSTextStorage?
        let resolvedContainer: NSTextContainer
        if let container {
            storage = nil
            resolvedContainer = container
        } else {
            let newStorage = NSTextStorage()
            let manager = NSLayoutManager()
            resolvedContainer = NSTextContainer(size: NSSize(width: max(1, frameRect.width),
                                                              height: CGFloat.greatestFiniteMagnitude))
            newStorage.addLayoutManager(manager)
            manager.addTextContainer(resolvedContainer)
            storage = newStorage
        }
        super.init(frame: frameRect, textContainer: resolvedContainer)
        ownedTextStorage = storage
        resolvedContainer.widthTracksTextView = true
        resolvedContainer.heightTracksTextView = false
        isRichText = false; allowsUndo = false; importsGraphics = false
        drawsBackground = false; textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isVerticallyResizable = false; isHorizontallyResizable = false
        insertionPointColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyInitialFocusIfNeeded()
    }
    func applyInitialFocusIfNeeded() {
        guard isEditable, initialFocus, !appliedInitialFocus, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditable, !self.appliedInitialFocus else { return }
            self.appliedInitialFocus = true
            self.window?.makeFirstResponder(self)
            self.selectAll(nil)
        }
    }
    private var bytes: [UInt8] { Array(string.data(using: .macOSRoman) ?? Data()) }
    private var byteSelection: Range<Int> {
        let selection = selectedRange()
        return selection.location..<(selection.location + selection.length)
    }
    private var clipboard: [UInt8]? {
        NSPasteboard.general.string(forType: .string)?.data(using: .macOSRoman).map(Array.init)
    }
    private func width(_ bytes: [UInt8]) -> Int {
        BitmapFont.bold14?.width(String(data: Data(bytes), encoding: .macOSRoman) ?? "") ?? 0
    }
    static func originalKeyByte(_ characters: String) -> UInt8? {
        switch characters {
        case "\u{f700}": return 30
        case "\u{f701}": return 31
        case "\u{f702}": return 28
        case "\u{f703}": return 29
        case "\u{f728}": return 127
        default:
            guard let data = characters.data(using: .macOSRoman), data.count == 1 else { return nil }
            return data[0]
        }
    }
    override func keyDown(with event: NSEvent) {
        guard isEditable else { return }
        guard let characters = event.characters, let byte = Self.originalKeyByte(characters) else {
            // Text input services can compose a MacRoman accented character.
            super.keyDown(with: event)
            return
        }
        var rules = readRules()
        let action = rules.key(byte, command: event.modifierFlags.contains(.command),
            text: bytes, selection: byteSelection, clipboard: clipboard ?? [], width: width)
        writeRules(rules)
        // The menu system already had its chance to handle a command. Do not
        // give NSTextView an invented Cmd-A/Undo text command as a fallback.
        if action != .unhandled { perform(action) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable, window?.firstResponder === self else { return false }
        guard event.modifierFlags.contains(.command),
              let character = event.charactersIgnoringModifiers?.lowercased(), ["x", "c", "v", "."].contains(character) else {
            return false
        }
        if character == "v", clipboard == nil { NSSound.beep(); return true }
        var rules = readRules()
        let action = rules.key(character.utf8.first!, command: true, text: bytes,
            selection: byteSelection, clipboard: clipboard ?? [], width: width)
        writeRules(rules); perform(action)
        return true
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if applyingOriginalAction { super.insertText(insertString, replacementRange: replacementRange); return }
        guard isEditable else { return }
        let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
        guard let data = text.precomposedStringWithCanonicalMapping.data(using: .macOSRoman) else { NSSound.beep(); return }
        if replacementRange.location != NSNotFound { setSelectedRange(replacementRange) }
        for byte in data {
            var rules = readRules()
            let action = rules.key(byte, text: bytes, selection: byteSelection, width: width)
            writeRules(rules); perform(action)
        }
    }
    override func paste(_ sender: Any?) {
        guard isEditable, let clipboard else { NSSound.beep(); return }
        perform(readRules().paste(clipboard, text: bytes, selection: byteSelection, fromMenu: true, width: width))
    }
    override func delete(_ sender: Any?) { guard isEditable else { return }; perform(.clearAll) }
    private func perform(_ action: OriginalTextEditRules.Action) {
        switch action {
        case .insert(let bytes):
            applyingOriginalAction = true
            super.insertText(String(data: Data(bytes), encoding: .macOSRoman) ?? "", replacementRange: selectedRange())
            applyingOriginalAction = false
        case .textEditKey(8): super.deleteBackward(nil)
        case .textEditKey(28): super.moveLeft(nil)
        case .textEditKey(29): super.moveRight(nil)
        case .nextField: focusGroup?.move(from: fieldIndex, direction: 1)
        case .previousField: focusGroup?.move(from: fieldIndex, direction: -1)
        case .copy: super.copy(nil)
        case .cut: super.cut(nil)
        case .clearAll: super.selectAll(nil); super.deleteBackward(nil)
        case .beep: NSSound.beep()
        default: break
        }
    }
    override func didChangeText() {
        super.didChangeText()
        applyOriginalAdvances()
        changed(string)
    }
    func applyOriginalAdvances() {
        guard let storage = textStorage else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 15; paragraph.maximumLineHeight = 15
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [.font: metricFont, .foregroundColor: NSColor.clear,
            .ligature: 0, .paragraphStyle: paragraph]
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        for index in 0..<storage.length {
            let range = NSRange(location: index, length: 1)
            let character = (string as NSString).substring(with: range)
            let native = (character as NSString).size(withAttributes: [.font: metricFont]).width
            let target = CGFloat(BitmapFont.bold14?.width(character) ?? Int(native))
            storage.addAttribute(.kern, value: target - native, range: range)
        }
        typingAttributes = attributes
    }
}
#else
import UIKit

private final class OriginalRegistrationTouchEditor: UITextField {
    var originalPaste: (Bool) -> Void = { _ in }
    override func paste(_ sender: Any?) { originalPaste(true) }
    @objc private func keyboardPaste() { originalPaste(false) }
    override var keyCommands: [UIKeyCommand]? {
        let paste = UIKeyCommand(input: "v", modifierFlags: .command, action: #selector(keyboardPaste))
        paste.wantsPriorityOverSystemBehavior = true
        return [paste] + (super.keyCommands ?? [])
    }
}

private struct OriginalRegistrationTouchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var rules: OriginalTextEditRules.State
    let label: String
    let initialFocus: Bool
    let enabled: Bool
    let focusGroup: OriginalRegistrationFocusGroup
    let fieldIndex: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> OriginalRegistrationTouchEditor {
        let field = OriginalRegistrationTouchEditor()
        field.delegate = context.coordinator
        field.font = .init(name: "TimesNewRomanPS-BoldMT", size: 14)
        field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.textColor = .clear; field.tintColor = .black
        focusGroup.register(fieldIndex) { [weak field] in
            guard let field, field.isEnabled else { return }
            field.becomeFirstResponder(); field.selectAll(nil)
        }
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        if initialFocus { DispatchQueue.main.async { field.becomeFirstResponder() } }
        return field
    }
    func updateUIView(_ field: OriginalRegistrationTouchEditor, context: Context) {
        context.coordinator.owner = self
        field.originalPaste = { [weak field, weak coordinator = context.coordinator] fromMenu in
            guard let field else { return }
            coordinator?.paste(field, fromMenu: fromMenu)
        }
        if field.text != text { field.text = text }
        field.accessibilityLabel = label; field.isEnabled = enabled
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var owner: OriginalRegistrationTouchField
        init(_ owner: OriginalRegistrationTouchField) { self.owner = owner }
        @objc func changed(_ field: UITextField) { owner.text = field.text ?? "" }
        func paste(_ field: UITextField, fromMenu: Bool) {
            guard field.isEnabled, let selected = field.selectedTextRange,
                  let old = (field.text ?? "").data(using: .macOSRoman),
                  let clipboard = UIPasteboard.general.string?.data(using: .macOSRoman) else { return }
            let start = field.offset(from: field.beginningOfDocument, to: selected.start)
            let end = field.offset(from: field.beginningOfDocument, to: selected.end)
            let action = owner.rules.paste(Array(clipboard), text: Array(old), selection: start..<end, fromMenu: fromMenu) {
                BitmapFont.bold14?.width(String(data: Data($0), encoding: .macOSRoman) ?? "") ?? 0
            }
            guard case .insert(let inserted) = action else { return }
            var bytes = Array(old); bytes.replaceSubrange(start..<end, with: inserted)
            let result = String(data: Data(bytes), encoding: .macOSRoman) ?? ""
            field.text = result; owner.text = result
            if let position = field.position(from: field.beginningOfDocument, offset: start + inserted.count) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            let bytes = Array((field.text ?? "").data(using: .macOSRoman) ?? Data())
            _ = owner.rules.key(13, text: bytes, selection: 0..<0) { _ in 0 }
            owner.focusGroup.move(from: owner.fieldIndex, direction: 1)
            return false
        }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard let old = field.text?.data(using: .macOSRoman), let replacement = string.data(using: .macOSRoman) else { return false }
            if replacement.isEmpty {
                _ = owner.rules.key(8, text: Array(old), selection: range.location..<(range.location + range.length)) { _ in 0 }
                return true
            }
            var bytes = Array(old), selection = range.location..<(range.location + range.length)
            for byte in replacement {
                let action = owner.rules.key(byte, text: bytes, selection: selection) {
                    BitmapFont.bold14?.width(String(data: Data($0), encoding: .macOSRoman) ?? "") ?? 0
                }
                guard case .insert(let inserted) = action else { return false }
                bytes.replaceSubrange(selection, with: inserted)
                let next = selection.lowerBound + inserted.count
                selection = next..<next
            }
            return true
        }
    }
}
#endif
