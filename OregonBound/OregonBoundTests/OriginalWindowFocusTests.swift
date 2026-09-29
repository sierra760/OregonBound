import Testing
@testable import OregonBound

struct OriginalWindowFocusTests {
    @Test func duplicateAndOtherWindowEventsDoNotUndoActivityLocks() {
        var menu = OriginalFileMenuRules.State()
        menu.beginJourney(); menu.beginBlockingActivity()
        let before = menu
        menu.activateWindow(true,stage: .journey)
        #expect(menu == before) // active and already uninhibited: CODE1:1a02.
        menu.activateWindow(false,stage: .journey,isGameWindow: false)
        #expect(menu == before) // CODE1:19ec rejects another window.
        menu.activateWindow(true,stage: .journey,isGameWindow: false)
        #expect(menu == before)
    }

    @Test func genuineFocusEdgesRewriteOnlyLoadAndExitAndRememberInactiveState() {
        var menu = OriginalFileMenuRules.State()
        menu.beginJourney()
        menu.activateWindow(false,stage: .journey)
        #expect(menu.windowInactive && menu.enabled == [.save,.exportLog,.quit])
        let inactive = menu
        menu.activateWindow(false,stage: .journey)
        #expect(menu == inactive)
        menu.activateWindow(true,stage: .journey)
        #expect(!menu.windowInactive && menu.enabled == [.save,.exportLog,.exitGame,.quit])
        menu.beginBlockingActivity()
        menu.activateWindow(false,stage: .journey)
        menu.activateWindow(true,stage: .journey)
        // Literal CODE1:1a0c: a genuine focus cycle can re-enable Exit while the
        // other three activity-locked File items stay disabled.
        #expect(menu.enabled == [.exitGame])
    }

    @Test func returnFocusUsesCurrentStageWithoutRestoringAnOldMenuSnapshot() {
        var menu = OriginalFileMenuRules.State()
        menu.activateWindow(false,stage: .attract)
        #expect(menu.enabled == [.quit])
        menu.activateWindow(true,stage: .attract)
        #expect(menu.enabled == [.load,.quit])
        menu.activateWindow(false,stage: .attract)
        menu.beginSetup()
        menu.activateWindow(true,stage: .setup)
        #expect(menu.enabled == [.exitGame,.quit])
    }

    @Test func aboutUsesHostFactsWithoutInventingClassicHeapMeasurements() {
        #expect(OriginalAboutRules.systemInformation(machineType: "Mac14,2",processor: "Apple M2",systemVersion: "macOS 14.7")
            == ["Mac14,2","Apple M2","macOS 14.7","N/A","N/A","N/A","N/A"])
        #expect(OriginalAboutRules.systemInformation(machineType: "",processor: "",systemVersion: "").prefix(3)
            == ["Unavailable","Unavailable","Unavailable"])
    }
}

#if os(macOS)
import AppKit

@MainActor struct OriginalWindowGeometryTests {
    @Test func attachingWindowKeepsCanvasAspectConstraint() {
        let canvas = CGSize(width: 512, height: 322)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let geometry = OriginalWindowGeometry.GeometryView(canvas: canvas)
        window.contentView = geometry
        defer { window.contentView = nil }
        #expect(window.contentAspectRatio == canvas)
        #expect(window.contentMinSize == canvas)
        let content = window.contentRect(forFrameRect: window.frame)
        #expect(abs(content.height - content.width * canvas.height / canvas.width) <= 1)
    }
}
#endif
