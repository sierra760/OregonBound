import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// ALRT/DITL2003 CONTENT ONLY,300x125. Parent places this over the main game
/// window and supplies System modal framing outside its bounds. No backdrop
/// dimming, title, timeout, or Escape/Cmd-period shortcut is introduced here.
struct OriginalManagementAlertContents: View {
    let presentation: OriginalManagementAlerts.Presentation
    let dismiss: () -> Void
    @State private var dismissed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if let icon = icon {
                icon.resizable().interpolation(.none).frame(width:32,height:32)
                    .offset(x:20,y:10).accessibilityHidden(true)
            }
            OriginalText(text:presentation.text,font:.chicago12,width:223)
                .frame(width:223,height:83,alignment:.topLeading).clipped().offset(x:72,y:7)
            OriginalButton(title:"OK",isDefault:true,paper:.white,action:finish)
                .frame(width:60,height:20).offset(x:120,y:100)
                .keyboardShortcut(.defaultAction)
        }
        .frame(width:300,height:125,alignment:.topLeading)
        .foregroundStyle(.black)
        // This IS the nested modal. The inherited originalModalDispatchBlocked
        // blocks background game dispatch, not this alert's own OK button.
    }

    private var icon: Image? {
        let name = "system7_alert_icon_\(presentation.icon.rawValue)"
        guard let url = GameData.url(forResource:name,withExtension:"png",subdirectory:"system_controls") else { return nil }
        #if os(macOS)
        guard let value = NSImage(contentsOf:url) else { return nil }
        return Image(nsImage:value)
        #else
        guard let value = UIImage(contentsOfFile:url.path) else { return nil }
        return Image(uiImage:value)
        #endif
    }
    private func finish() {
        guard !dismissed else { return }
        dismissed = true
        dismiss()
    }
}
