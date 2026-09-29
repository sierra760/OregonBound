#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import OregonBound

@MainActor final class OriginalRiverPresentationRenderingTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    private func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }
    private func ink(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> Bool {
        let c = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        return c.redComponent + c.greenComponent + c.blueComponent < 1.5
    }
    private func compare(_ actual: NSBitmapImageRep, _ expected: NSBitmapImageRep,
                         x: Int, y: Int, width: Int, height: Int,
                         expectedX: Int? = nil, expectedY: Int? = nil) throws {
        var differences = 0
        for row in 0..<height {
            for column in 0..<width {
                if try ink(actual,x+column,y+row) != ink(expected,(expectedX ?? x)+column,(expectedY ?? y)+row) {
                    differences += 1
                }
            }
        }
        XCTAssertEqual(differences, 0, "Source-authored ink at (\(x),\(y),\(width),\(height))")
    }
    private func outcome(_ status: Int = 0) -> OriginalRiverRules.Outcome {
        .init(requestedMethodRaw: 1, animationMethodRaw: 1, failureKind: status == 0 ? 0 : 2,
              status: status, currentFactor: 0, presentationRandomTicks: status == 0 ? nil : 90)
    }

    func testProductionCrossingCaptionUsesSourceFontAndTextBoxPosition() throws {
        var choice = outcome()
        choice.phase = .animation
        let actual = try render(OriginalCrossingPane(trip: Journey(seed: 1), outcome: choice,
                                                   prepareResult: {}, complete: {}))
        let expected = try render(ZStack(alignment: .topLeading) {
            originalPaper
            // Source DITL5400 item(3,12,256,17), centered bold14 width135;
            // TextBox adds1+floor((256-135-1)/2)=61 to item x3.
            OriginalText(text: "Crossing the river…", font: .bold14).offset(x: 64, y: 170)
        }.frame(width: 262, height: 199))
        try compare(actual,expected,x:3,y:170,width:256,height:17)
        for y in [155,157] { XCTAssertTrue(try ink(actual,100,y), "Original pane black edge at y\(y)") }
        let orange = try XCTUnwrap(actual.colorAt(x: 100,y: 156)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(orange.redComponent, 0.8)
        XCTAssertLessThan(orange.blueComponent, 0.2)
    }

    func testRestoredResultsSkipAnimationForNewAndLegacySaves() throws {
        for phase: OriginalRiverRules.Phase? in [nil, .result] {
            var saved = outcome()
            saved.phase = phase
            let actual = try render(OriginalCrossingPane(trip: Journey(seed: 1), outcome: saved,
                prepareResult: { XCTFail("Restored result must not prepare again") }, complete: {}))
            let expected = try render(OriginalRiverResultPane(
                content: .init(outcome: saved, names: []), requestDismissal: {}))
            try compare(actual,expected,x:12,y:73,width:236,height:64)
            try compare(actual,expected,x:96,y:164,width:68,height:28)
        }
    }

    func testSafeAndFailureResultHeadingsAndBothDefaultRings() throws {
        let button = try render(OriginalButton(title: "OK", isDefault: true, action: {})
            .frame(width:60,height:20).padding(4).background(originalPaper))
        for status in [0,1,2] {
            let content = OriginalRiverResultContent(outcome: outcome(status), names: [])
            let actual = try render(OriginalRiverResultPane(content: content, requestDismissal: {}))
            try compare(actual,button,x:96,y:164,width:68,height:28,expectedX:0,expectedY:0)
            if status == 0 {
                let expected = try render(ZStack(alignment: .topLeading) {
                    originalPaper
                    OriginalText(text: "You made it safely across the ", font: .bold14).offset(x:13,y:73)
                    OriginalText(text: "river.", font: .bold14).offset(x:13,y:88)
                }.frame(width:262,height:199))
                try compare(actual,expected,x:12,y:73,width:236,height:64)
                let capture = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(actual.cgImage), size: .init(width:262,height:199)))
                capture.name = "Original safe river result content"
                capture.lifetime = .keepAlways
                add(capture)
            } else {
                let expected = try render(ZStack(alignment: .topLeading) {
                    originalPaper
                    OriginalText(text: "Your wagon tipped over while crossing the river.", font: .plain12)
                        .offset(x:11,y:8)
                }.frame(width:262,height:199))
                try compare(actual,expected,x:10,y:8,width:242,height:17)
            }
        }
    }

    func testGenericDITLStaticTextUsesRecoveredTextBoxWrappingAndOrigin() throws {
        let actual = try render(OriginalDialogContents(resource: 6320,
            substitutions: ["You made it safely across the river"]) { _ in }
            .frame(width:262,height:199))
        let expected = try render(ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text: "You made it safely across the ", font: .bold14).offset(x:13,y:73)
            OriginalText(text: "river.", font: .bold14).offset(x:13,y:88)
        }.frame(width:262,height:199))
        try compare(actual,expected,x:12,y:73,width:236,height:64)
    }

    func testGenericDITLStaticTextClipsAtAuthoredBottom() throws {
        let actual = try render(OriginalDialogContents(resource: 6320,
            substitutions: [Array(repeating: "A", count: 9).joined(separator: "\r")]) { _ in }
            .frame(width:262,height:199))
        // DITL6320 ends its text rectangle at137, before the default OK ring164.
        var escapedPixels = 0
        for y in 137..<164 {
            for x in 12..<248 { if try ink(actual,x,y) { escapedPixels += 1 } }
        }
        XCTAssertEqual(escapedPixels, 0, "Text escaped DITL6320's authored bottom137")
    }

    func testHelpDialogsUseInheritedBold12() throws {
        let fixtures: [(Int, String, Int, Int, Int)] = [
            (6040, "Filling — Meals are large and generous.", 12, 18, 231),
            (6060, "Steady —", 12, 6, 55),
            (8075, "River Crossing Help", 71, 3, 119)
        ]
        for (resource,text,x,y,width) in fixtures {
            let actual = try render(OriginalDialogContents(resource:resource) { _ in }
                .frame(width:262,height:304))
            let expected = try render(ZStack(alignment:.topLeading) {
                originalPaper
                OriginalText(text:text,font:.bold12).offset(x:CGFloat(x),y:CGFloat(y))
            }.frame(width:262,height:304))
            try compare(actual,expected,x:x,y:y,width:width,height:12)
        }
    }

    func testPreparationAndRestMessagesUseOriginalCenteredPositions() throws {
        let fixtures: [(Int, String, Int, Int, Int)] = [
            (9161, "Get ready to hunt…", 178, 125, 133),
            (9201, "Get ready to go rafting…", 160, 125, 168),
            (9201, "Use the mouse to move your raft to avoid the rocks.", 71, 175, 346),
            (9202, "Pulling up onshore...", 176, 125, 136),
            (5221, "You may rest for 1 to 9 days.", 35, 36, 192)
        ]
        for (resource,text,x,y,width) in fixtures {
            let actual = try render(OriginalDialogContents(resource:resource,substitutions:["Pulling up onshore"]) { _ in }
                .frame(width:494,height:304))
            let expected = try render(ZStack(alignment:.topLeading) {
                originalPaper
                OriginalText(text:text,font:.bold14).offset(x:CGFloat(x),y:CGFloat(y))
            }.frame(width:494,height:304))
            try compare(actual,expected,x:x,y:y,width:width,height:15)
        }
    }

    func testFastTextBoxDoesNotInstallAuthoredHeightClipping() throws {
        let actual = try render(ZStack(alignment:.topLeading) {
            originalPaper
            OriginalTextBox(text:"Hello",font:.bold14,width:100,height:3)
        }.frame(width:100,height:20))
        let expected = try render(ZStack(alignment:.topLeading) {
            originalPaper
            OriginalText(text:"Hello",font:.bold14).offset(x:1)
        }.frame(width:100,height:20))
        try compare(actual,expected,x:0,y:0,width:100,height:20)
    }

    func testFailureLossColumnUsesOriginalDrawStringPositions() throws {
        var failure = outcome(2)
        failure.losses = [3,1,2000,0,1,0,1234]
        failure.drownedMembers = [1]
        let content = OriginalRiverResultContent(outcome: failure, names: ["Leader","Anna"])
        let actual = try render(OriginalRiverResultPane(content: content, requestDismissal: {}))
        let expected = try render(ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text:"You lost:",font:.plain12).offset(x:10,y:30)
            OriginalText(text:"2 oxen",font:.plain12).offset(x:60,y:30)
            OriginalText(text:"1 set of clothing",font:.plain12).offset(x:60,y:42)
            OriginalText(text:"2,000 bullets",font:.plain12).offset(x:60,y:54)
            OriginalText(text:"1 wagon axle",font:.plain12).offset(x:60,y:66)
            OriginalText(text:"1,234 pounds of food",font:.plain12).offset(x:60,y:78)
            OriginalText(text:"Anna (drowned)",font:.plain12).offset(x:60,y:90)
        }.frame(width:262,height:199))
        try compare(actual,expected,x:10,y:30,width:241,height:130)
        let capture = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(actual.cgImage), size: .init(width:262,height:199)))
        capture.name = "Original failed river result content"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
#endif

#if os(macOS)
@MainActor final class OriginalRiverLifecycleTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    private final class Model: ObservableObject {
        @Published var outcome = OriginalRiverRules.Outcome(
            requestedMethodRaw: 1, animationMethodRaw: 1, failureKind: 0,
            status: 0, currentFactor: 0)
    }
    private struct Harness: View {
        @ObservedObject var model: Model
        let complete: () -> Void
        var body: some View {
            OriginalCrossingPane(trip: Journey(seed: 1), outcome: model.outcome,
                prepareResult: { model.outcome.phase = .result }, complete: complete)
                .environment(\.scenePhase, .active)
        }
    }

    func testAnimatedCrossingResultDismissesAfterBranchReplacement() async throws {
        try await checkDismissal(status: 0)
    }

    func testFailedCrossingDismissesAfterBranchReplacement() async throws {
        try await checkDismissal(status: 2)
    }

    func testWetSuppliesResultDismissesAfterBranchReplacement() async throws {
        try await checkDismissal(status: 4)
    }

    func testSavedResultDismissesWithoutReplayingAnimation() async throws {
        try await checkDismissal(status: 0, restored: true)
    }

    func testOKClosesResultBeforeAutomaticTimeout() async throws {
        try await checkDismissal(status: 0, pressOK: true)
    }

    private func checkDismissal(status: Int, restored: Bool = false, pressOK: Bool = false) async throws {
        let model = Model()
        model.outcome.status = status
        model.outcome.failureKind = status == 2 ? 2 : 0
        model.outcome.presentationRandomTicks = status == 2 ? 90 : nil
        model.outcome.phase = restored ? .result : .animation
        let finished = expectation(description: "Crossing result closes")
        finished.assertForOverFulfill = true
        let host = NSHostingView(rootView: Harness(model: model) { finished.fulfill() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 262, height: 199),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        // Mount the animation, then exercise the real animation-to-result update.
        try await Task.sleep(nanoseconds: 200_000_000)
        model.outcome.phase = .result
        if pressOK {
            try await Task.sleep(nanoseconds: 100_000_000)
            let point = host.convert(NSPoint(x: 130, y: host.isFlipped ? 178 : 21), to: nil)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.postEvent(event, atStart: false)
            }
        }
        await fulfillment(of: [finished], timeout: pressOK ? 1 : 6)
    }
}
#endif
