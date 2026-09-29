#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import OregonBound

@MainActor final class OriginalPreferencesRenderingTests: XCTestCase {
    func testGuideIndexButtonsMatchOriginalCapturedInk() throws {
        let url = try GameDataTestSupport.referenceCapture(
            named: "original-guide-index", withExtension: "png")
        let original = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let renderer = ImageRenderer(content: OriginalGuideIndex(selection: 1, initialRow: 0,
            select: { _ in }, accept: {}, cancel: {}).background(originalPaper))
        renderer.scale = 1
        let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        func ink(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> Bool {
            let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return c.redComponent + c.greenComponent + c.blueComponent < 1.5
        }
        var mismatches: [String] = []
        // Original pane starts (138,309). Limit the comparison to the authored
        // button rectangles; the pointer beside OK is not application artwork.
        for (left,top) in [(166,130),(167,160)] {
            for y in top..<top+20 {
                for x in left..<left+80 where try ink(rendered,x,y) != ink(original,138+x,309+y) {
                    mismatches.append("(\(x),\(y))")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "\(mismatches.count) differing guide-button ink pixels; first: \(mismatches.prefix(12))")
    }

    /// The full pane catches fractional push-button title placement and the
    /// modern rounded default-ring replacement, beyond the radio-only checks.
    func testWholePaneMatchesOriginalCapturedInk() throws {
        let url = try GameDataTestSupport.referenceCapture(
            named: "original-time-options-2026-09-19", withExtension: "jpg")
        let original = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let renderer = ImageRenderer(content: OriginalPreferencesPane(
            timing: .init(speed: .medium, huntTime: .seconds45), save: { _ in }, cancel: {}))
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.cgImage)
        let rendered = NSBitmapImageRep(cgImage: image)
        func ink(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> Bool {
            let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return c.redComponent + c.greenComponent + c.blueComponent < 1.5
        }
        var mismatches: [String] = []
        for y in 0..<200 {
            for x in 0..<210 where try ink(rendered,x,y) != ink(original,407+x,303+y) {
                mismatches.append("(\(x),\(y))")
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "\(mismatches.count) differing ink pixels; first: \(mismatches.prefix(12))")
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .init(width:210,height:200)))
        attachment.name = "Complete Time Options content at original scale"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Exercises the actual production pane. Reinstating its former Circle /
    /// HStack or solid group frame must disagree with the original capture.
    func testRadioControlsAndGroupFrameMatchOriginalCapturedInk() throws {
        let url = try GameDataTestSupport.referenceCapture(
            named: "original-time-options-2026-09-19", withExtension: "jpg")
        let original = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let pane = OriginalPreferencesPane(timing: .init(speed: .medium, huntTime: .seconds45),
                                           save: { _ in }, cancel: {})
        let renderer = ImageRenderer(content: pane)
        renderer.scale = 1
        renderer.isOpaque = true
        let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        XCTAssertEqual(rendered.pixelsWide, 210)
        XCTAssertEqual(rendered.pixelsHigh, 200)
        func ink(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> Bool {
            let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return c.redComponent + c.greenComponent + c.blueComponent < 1.5
        }
        // The untouched original screenshot's dialog content starts (407,303).
        // Threshold only separates black/white ink; it does not assert JPEG RGB equality.
        var mismatches: [String] = []
        for top in [50,70,90] {
            for y in top..<top+15 {
                for x in 70..<145 where try ink(rendered,x,y) != ink(original,407+x,303+y) {
                    mismatches.append("radio(\(x),\(y))")
                }
            }
        }
        for (left,top,width,height) in [(63,5,85,15),(49,30,114,20)] {
            for y in top..<top+height {
                for x in left..<left+width where try ink(rendered,x,y) != ink(original,407+x,303+y) {
                    mismatches.append("static(\(x),\(y))")
                }
            }
        }
        for y in 37..<111 {
            for x in 41..<173 where x == 41 || x == 172 || y == 37 || y == 110 {
                if try ink(rendered,x,y) != ink(original,407+x,303+y) {
                    mismatches.append("group(\(x),\(y))")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty,
                      "\(mismatches.count) differing ink pixels; first: \(mismatches.prefix(12))")
        let attachment = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(renderer.cgImage), size: .init(width:210,height:200)))
        attachment.name = "Actual Time Options pane at original scale"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
