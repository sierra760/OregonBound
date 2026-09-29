#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import OregonBound

@MainActor struct OriginalJournalWheelInputTests {
    private func wheel(in view: NSView) -> JournalWheelInput.View? {
        if let receiver = view as? JournalWheelInput.View { return receiver }
        return view.subviews.lazy.compactMap { wheel(in: $0) }.first
    }

    /// A hidden real host exercises SwiftUI's hit-test bridge without changing
    /// the foreground app, showing a window, or calling the receiver directly.
    private func hosted<Content: View>(_ content: Content) -> (NSWindow, NSHostingView<Content>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 262, height: 102)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private func event(_ delta: Int32, precise: Bool = false) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                                     wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
        return try #require(NSEvent(cgEvent: cg))
    }

    @Test func productionPaneRoutesWheelThroughNativeHitTestingInBothDirections() throws {
        let (window, host) = hosted(OriginalJournalPane(entries: [], departureMonth: 4))
        defer { window.contentView = nil }
        let receiver = try #require(wheel(in: host))
        var lines: [Int] = []
        receiver.action = { lines.append($0) }
        let point = host.convert(NSPoint(x: 100, y: 50), from: receiver)
        let target = try #require(host.hitTest(point))
        #expect(target === receiver)
        target.scrollWheel(with: try event(-3))
        target.scrollWheel(with: try event(3))
        #expect(lines == [3, -3])
        // The overlay must not cover the separately interactive scrollbar.
        let scrollbarPoint = host.convert(NSPoint(x: 255, y: 50), from: receiver)
        #expect(host.hitTest(scrollbarPoint) !== receiver)
    }

    @Test func preciseWheelAccumulatesBeforeMovingOneJournalLine() throws {
        let (window, host) = hosted(OriginalJournalPane(entries: [], departureMonth: 4))
        defer { window.contentView = nil }
        let receiver = try #require(wheel(in: host))
        var lines: [Int] = []
        receiver.action = { lines.append($0) }
        let target = try #require(host.hitTest(host.convert(NSPoint(x: 100, y: 50), from: receiver)))
        let halfLine = try event(-6, precise: true)
        #expect(halfLine.hasPreciseScrollingDeltas)
        target.scrollWheel(with: halfLine)
        #expect(lines.isEmpty)
        target.scrollWheel(with: halfLine)
        #expect(lines == [1])
    }

    @Test func modalHitTestingBlockExcludesJournalReceiver() throws {
        let (window, host) = hosted(OriginalJournalPane(entries: [], departureMonth: 4).allowsHitTesting(false))
        defer { window.contentView = nil }
        let receiver = try #require(wheel(in: host))
        let point = host.convert(NSPoint(x: 100, y: 50), from: receiver)
        #expect(host.hitTest(point) !== receiver)
    }
}
#endif

#if os(macOS)
import XCTest

@MainActor final class OriginalJournalLiveUpdateTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var entries: [JournalEntry] = []
    }
    private struct Harness: View {
        @ObservedObject var model: Model
        var body: some View { OriginalJournalPane(entries: model.entries, departureMonth: 4) }
    }
    private func pixels(_ host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return Data(bytes: try XCTUnwrap(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    func testNewRecordAppearsWithoutWaitingForAnotherJournalChange() async throws {
        try GameDataTestSupport.requireGameData()
        let model = Model()
        let host = NSHostingView(rootView: Harness(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 262, height: 102),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = try pixels(host)
        model.entries = [.init(id: 1, day: 0, text: "Fresh trail report")]
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(try pixels(host), before, "The new record must render on the first update")
    }
}
#endif
