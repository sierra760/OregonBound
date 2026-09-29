import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared original button geometry on the system dialogs' white paper.
struct OriginalManagementButton: View {
    let title: String
    var width: CGFloat = 60
    var isDefault = false
    var enabled = true
    let action: () -> Void
    var body: some View {
        OriginalButton(title: title, isDefault: isDefault, paper: .white, action: action)
            .frame(width: width, height: 20).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }
}

/// Authored labels and the held-button Hunt Time popup use recovered System7
/// geometry and the original Chicago12 strike.
struct OriginalPreferencesPane: View {
    @State private var draft: OriginalPreferences.Timing
    @State private var error: String?
    @State private var popupTracking = false
    let save: (OriginalPreferences.Timing) throws -> Void
    let cancel: () -> Void
    init(timing: OriginalPreferences.Timing, save: @escaping (OriginalPreferences.Timing) throws -> Void,
         cancel: @escaping () -> Void) {
        _draft = State(initialValue: timing); self.save = save; self.cancel = cancel
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            // Original static-item ink starts one pixel inside the authored
            // left edge, confirmed against the System7 dialog capture.
            OriginalText(text: "Time Options", font: .chicago12).offset(x: 1)
                .frame(width: 85, height: 15, alignment: .topLeading).offset(x: 63, y: 5)
            // CODE15:16a4–16b0: PenPat(qd.gray), FrameRect, PenNormal.
            OriginalSystemGroupFrame(width: 132, height: 74).offset(x: 41, y: 37)
            OriginalText(text: "Simulation Speed", font: .chicago12).offset(x: 1)
                .frame(width: 114, height: 20, alignment: .topLeading).background(.white).offset(x: 49, y: 30)
            ForEach(Array([OriginalPreferences.Speed.slow, .medium, .fast].enumerated()), id: \.offset) { index, speed in
                OriginalSystemRadio(title: speed.title, selected: draft.speed == speed,
                                    interactionEnabled: !popupTracking) {
                    draft.speed = speed
                }.offset(x: 70, y: CGFloat(50 + index * 20))
            }
            OriginalHuntTimePopup(selection: Binding(
                get: { Int(draft.huntTime.rawValue) },
                set: { if let time = OriginalPreferences.HuntTime(rawValue: UInt8(clamping: $0)) { draft.huntTime = time } }),
                trackingChanged: { popupTracking = $0 })
                .offset(x: 8, y: 130).zIndex(1)
            OriginalManagementButton(title: "Cancel", width: 80, action: cancel).offset(x: 20, y: 175)
                .keyboardShortcut(".", modifiers: .command).disabled(popupTracking)
            OriginalManagementButton(title: "OK", width: 80, isDefault: true) {
                do { try save(draft) } catch { self.error = error.localizedDescription }
            }.offset(x: 110, y: 175).keyboardShortcut(.defaultAction).disabled(popupTracking)
            if popupTracking {
                OriginalManagementAlertKeyboard(ready: false, dismiss: {})
                    .frame(width: 0, height: 0)
            }
        }.frame(width: 210, height: 200).font(.system(size: 12)).foregroundStyle(.black)
            .alert("Time Options", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct OriginalEnableManagementPane: View {
    let configuration: OriginalPreferences.Configuration
    let enable: (String) -> Bool
    let cancel: () -> Void
    let presentAlert: (OriginalManagementAlerts.Purpose) -> Void
    @State private var password = ""
    @StateObject private var focusGroup = OriginalManagementFocusGroup()
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            OriginalText(text: "Enable Management", font: .chicago12).frame(width: 136, height: 16, alignment: .topLeading).offset(x: 88, y: 6)
            OriginalText(text: "Password:", font: .chicago12).frame(width: 79, height: 18, alignment: .topLeading).offset(x: 39, y: 33)
            OriginalManagementTextField(label: "Password", text: $password, field: .enablePassword,
                focusGroup: focusGroup, legacyCompatibility: configuration.password.data(using: .macOSRoman) == nil,
                initialFocus: true, onDefault: attempt)
                .frame(width: 132, height: 17).overlay(Rectangle().inset(by: -2).stroke(.black))
                .offset(x: 128, y: 35)
            if !configuration.hint.isEmpty {
                OriginalText(text: "Hint:", font: .chicago12).frame(width: 60, height: 20, alignment: .topLeading).offset(x: 40, y: 59)
                Group {
                    if configuration.hint.data(using: .macOSRoman) != nil {
                        OriginalText(text: configuration.hint, font: .chicago12, width: 135)
                    } else { Text(configuration.hint) }
                }.frame(width: 135, height: 48, alignment: .topLeading).offset(x: 126, y: 60)
            }
            OriginalText(text: "Any changes you make to the Management Options will not take effect until players begin a new journey.", font: .chicago12, width: 288)
                .frame(width: 288, height: 52, alignment: .topLeading).offset(x: 13, y: 111)
            OriginalManagementButton(title: "Cancel", action: cancel).offset(x: 76, y: 170)
            OriginalManagementButton(title: "Enable", isDefault: true, action: attempt)
                .offset(x: 176, y: 170).keyboardShortcut(.defaultAction)
        }.frame(width: 312, height: 200).font(.system(size: 12)).foregroundStyle(.black)
    }
    private func attempt() {
        if !enable(password) {
            focusGroup.select(.enablePassword, range: 0..<2000)
            presentAlert(.enableIncorrectPassword)
        }
    }
}

struct OriginalChangePasswordPane: View {
    let configuration: OriginalPreferences.Configuration
    let save: (OriginalPreferences.Configuration) throws -> Void
    let cancel: () -> Void
    let presentAlert: (OriginalManagementAlerts.Purpose) -> Void
    @State private var old = ""
    @State private var new = ""
    @State private var hint: String
    @State private var error: String?
    @StateObject private var focusGroup = OriginalManagementFocusGroup()
    private var legacyCompatibility: Bool {
        configuration.password.data(using: .macOSRoman) == nil || configuration.hint.data(using: .macOSRoman) == nil
    }
    init(configuration: OriginalPreferences.Configuration,
         save: @escaping (OriginalPreferences.Configuration) throws -> Void, cancel: @escaping () -> Void,
         presentAlert: @escaping (OriginalManagementAlerts.Purpose) -> Void) {
        self.configuration = configuration; self.save = save; self.cancel = cancel
        self.presentAlert = presentAlert
        _hint = State(initialValue: configuration.hint)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            OriginalText(text: "Change Password", font: .chicago12).frame(width: 120, height: 21, alignment: .topLeading).offset(x: 94, y: 9)
            OriginalText(text: "Old Password:", font: .chicago12).frame(width: 98, height: 16, alignment: .topLeading).offset(x: 31, y: 40)
            OriginalText(text: "New Password:", font: .chicago12).frame(width: 106, height: 16, alignment: .topLeading).offset(x: 31, y: 70)
            OriginalText(text: "Hint (optional):", font: .chicago12).frame(width: 103, height: 20, alignment: .topLeading).offset(x: 31, y: 101)
            // DITL2044 uses ordinary visible edit items; only Enable uses hidden TE.
            OriginalManagementTextField(label: "Old Password", text: $old, field: .oldPassword,
                focusGroup: focusGroup, legacyCompatibility: legacyCompatibility, initialFocus: true)
                .frame(width: 135, height: 17).overlay(Rectangle().inset(by: -2).stroke(.black)).offset(x: 140, y: 40)
            OriginalManagementTextField(label: "New Password", text: $new, field: .newPassword,
                focusGroup: focusGroup, legacyCompatibility: legacyCompatibility)
                .frame(width: 135, height: 16).overlay(Rectangle().inset(by: -2).stroke(.black)).offset(x: 140, y: 70)
            OriginalManagementTextField(label: "Hint", text: $hint, field: .hint,
                focusGroup: focusGroup, legacyCompatibility: legacyCompatibility)
                .frame(width: 135, height: 48).overlay(Rectangle().inset(by: -2).stroke(.black)).offset(x: 140, y: 100)
            OriginalManagementButton(title: "Cancel", action: cancel).offset(x: 76, y: 165)
            OriginalManagementButton(title: "Change", isDefault: true, action: change).offset(x: 176, y: 165)
        }.frame(width: 312, height: 195).font(.system(size: 12)).foregroundStyle(.black)
            .alert("Change Password", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func change() {
        var updated = configuration
        if let error = updated.changePassword(old: old, new: new, hint: hint) {
            if error == .incorrect {
                focusGroup.select(.oldPassword, range: 0..<1000)
                presentAlert(.changeIncorrectPassword)
            } else { presentAlert(.emptyNewPassword) }
            return
        }
        do { try save(updated) } catch { self.error = error.localizedDescription }
    }
}
