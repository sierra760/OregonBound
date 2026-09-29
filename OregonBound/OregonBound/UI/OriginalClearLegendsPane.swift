#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// DITL2042 300×240 modal content. Geometry/operations are recovered; the
/// recovered Chicago12 strike supplies system labels and list text. StopAlert
/// 2045 has its own active System frame; the parent deactivates the editor frame.
/// Native list selection details remain a separate compatibility boundary.
struct OriginalClearLegendsPane: View {
    @State private var editor: OriginalLegendsManagement.Editor
    @State private var confirmingOriginal = false
    @State private var error: String?
    let restoreOriginal: () throws -> [OriginalEndingPresentation.Legend]
    let done: ([OriginalEndingPresentation.Legend]) throws -> Void
    let onConfirmationChanged: (Bool) -> Void

    init(legends: [OriginalEndingPresentation.Legend],
         restoreOriginal: @escaping () throws -> [OriginalEndingPresentation.Legend],
         done: @escaping ([OriginalEndingPresentation.Legend]) throws -> Void,
         onConfirmationChanged: @escaping (Bool) -> Void = { _ in }) {
        _editor = State(initialValue: .init(legends: legends))
        self.restoreOriginal = restoreOriginal
        self.done = done
        self.onConfirmationChanged = onConfirmationChanged
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Group {
                OriginalText(text: "Clear List of Legends", font: .chicago12)
                    .frame(width: 144, height: 20, alignment: .topLeading)
                    .offset(x: 79, y: 7)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.white)
                    ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            #if os(macOS)
                            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                            editor.select(index, extending: modifiers.contains(.command), range: modifiers.contains(.shift))
                            #else
                            editor.select(index, extending: false, range: false)
                            #endif
                        } label: {
                            let score = OriginalLegendsRules.scoreText(row.score)
                            let scoreWidth = CGFloat(BitmapFont.chicago12?.width(score) ?? 40)
                            let text = HStack(spacing: 4) {
                                OriginalText(text: row.name, font: .chicago12)
                                    .frame(width: max(0, 246 - scoreWidth), alignment: .leading).clipped()
                                OriginalText(text: score, font: .chicago12).fixedSize()
                            }.padding(.horizontal, 4).frame(width: 258, height: 16)
                                .background(.white)
                            if editor.selected.contains(row.id) { text.colorInvert() }
                            else { text }
                        }.buttonStyle(.plain).offset(x: 1, y: CGFloat(1 + index * 16))
                    }
                }.frame(width: 260, height: 162).clipped().overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                    .offset(x: 20, y: 30)
                managementButton("Original") { setConfirmation(true) }
                    .offset(x: 30, y: 210)
                managementButton("Remove", enabled: !editor.selected.isEmpty) { editor.removeSelected() }
                    .offset(x: 120, y: 210)
                managementButton("Done", isDefault: true) { finish() }
                    .offset(x: 210, y: 210).keyboardShortcut(.defaultAction)
                Button("Select All") { editor.selectAll() }.keyboardShortcut("a", modifiers: .command)
                    .frame(width: 0, height: 0).hidden().accessibilityHidden(true)
            }.disabled(confirmingOriginal)
                .allowsHitTesting(!confirmingOriginal).accessibilityHidden(confirmingOriginal)
            if confirmingOriginal {
                // Covered editor clicks never select rows or invoke controls.
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    #if os(macOS)
                    NSSound.beep()
                    #endif
                }.accessibilityHidden(true)
                OriginalSystemModalFrame(contentWidth: 270, contentHeight: 94) {
                    OriginalClearLegendsConfirmationContents { item in
                        if item == 2 { restore() } else { setConfirmation(false) }
                    }
                }
                // Content starts at (15,73); the frame extends eight pixels out.
                .offset(x: 7, y: 65)
                OriginalManagementAlertKeyboard(ready: true) { setConfirmation(false) }
                    .frame(width: 0, height: 0).disabled(error != nil)
            }
        }.frame(width: 300, height: 240).font(.system(size: 12)).foregroundStyle(.black)
            .onDisappear { onConfirmationChanged(false) }
            .alert("List of Legends", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func managementButton(_ title: String, enabled: Bool = true, isDefault: Bool = false,
                                  action: @escaping () -> Void) -> some View {
        OriginalManagementButton(title: title, isDefault: isDefault, enabled: enabled, action: action)
    }

    private func setConfirmation(_ value: Bool) {
        guard confirmingOriginal != value else { return }
        confirmingOriginal = value
        onConfirmationChanged(value)
    }

    private func restore() {
        do {
            editor.restored(try restoreOriginal())
            setConfirmation(false)
        } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        do { try done(editor.pendingRemovals) }
        catch { self.error = error.localizedDescription }
    }
}


/// CODE15:0878–08dc and ALRT/DITL2045. This is StopAlert ($a986), despite
/// the older recovery notes calling it NoteAlert. NIL filter defaults to No.
enum OriginalClearLegendsConfirmation {
    typealias Rect = OriginalManagementAlerts.Rect
    static let resourceID = 2045
    static let icon = OriginalManagementAlerts.Icon.stop
    static let text = "Are you sure you want to delete the current list?"
    static let contentBounds = Rect(top: 0, left: 0, bottom: 94, right: 270)
    static let messageBounds = Rect(top: 13, left: 65, bottom: 54, right: 265)
    static let iconBounds = Rect(top: 10, left: 20, bottom: 42, right: 52)
    static let noBounds = Rect(top: 65, left: 57, bottom: 85, right: 117)
    static let yesBounds = Rect(top: 65, left: 153, bottom: 85, right: 213)
    static let frameExtent = 8
    static let alertSoundCount = 0 // ALRT stage word $4444.
    static let waitsForApplicationAudio = false // Direct Toolbox call, no wrapper.

    static func response(to event: OriginalManagementAlerts.Event) -> OriginalManagementAlerts.Response {
        if case .button(2) = event { return .dismiss(item: 2) }
        return OriginalManagementAlerts.response(to: event)
    }

    /// CODE1:0208 center calculation, in the main game content coordinate space.
    /// The embedding window owns the source GrayRgn/fallback-screen decision.
    static func centeredContent(in host: Rect) -> Rect {
        let x = host.left + (host.width - contentBounds.width) / 2
        let y = host.top + (host.height - contentBounds.height) / 2
        return Rect(top: y, left: x, bottom: y + 94, right: x + 270)
    }
}

private struct OriginalClearLegendsConfirmationContents: View {
    let choose: (Int) -> Void
    private typealias Rules = OriginalClearLegendsConfirmation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if let icon {
                icon.resizable().interpolation(.none)
                    .frame(width: CGFloat(Rules.iconBounds.width), height: CGFloat(Rules.iconBounds.height))
                    .offset(x: CGFloat(Rules.iconBounds.left), y: CGFloat(Rules.iconBounds.top))
                    .accessibilityHidden(true)
            }
            OriginalText(text: Rules.text, font: .chicago12, width: Rules.messageBounds.width)
                .frame(width: CGFloat(Rules.messageBounds.width), height: CGFloat(Rules.messageBounds.height), alignment: .topLeading)
                .clipped().offset(x: CGFloat(Rules.messageBounds.left), y: CGFloat(Rules.messageBounds.top))
            OriginalManagementButton(title: "No", isDefault: true) { choose(1) }
                .offset(x: CGFloat(Rules.noBounds.left), y: CGFloat(Rules.noBounds.top))
                .keyboardShortcut(.defaultAction)
            OriginalManagementButton(title: "Yes") { choose(2) }
                .offset(x: CGFloat(Rules.yesBounds.left), y: CGFloat(Rules.yesBounds.top))
        }.frame(width: 270, height: 94).foregroundStyle(.black)
    }

    private var icon: Image? {
        guard let url = GameData.url(forResource: "system7_alert_icon_\(Rules.icon.rawValue)",
                                        withExtension: "png", subdirectory: "system_controls") else { return nil }
        #if os(macOS)
        guard let value = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: value)
        #else
        guard let value = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: value)
        #endif
    }
}
