#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import OregonBound

@MainActor final class OriginalRegistrationRenderingTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    func testTrailPaneGapsUseOriginalBlackOrangeBlackFrames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        for traveling in [false, true] {
            var trip = Journey(seed: 1)
            trip.phase = traveling ? .travel : .landmark
            let renderer = ImageRenderer(content: OriginalTrailView(game: game, trip: trip))
            renderer.scale = 1
            let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            // CODE5:3a12–3a86 outlines each recovered pane at outset2/orange
            // and outset1/black. These positions come from the root rect table.
            let gaps = [([61,62,63].map { ($0,100) }),
                        ([326,327,328].map { ($0,100) }),
                        ([448,449,450].map { ($0,100) }),
                        ((traveling ? [86,87,88] : [164,165,166]).map { (100,$0) }),
                        ([208,209,210].map { (100,$0) }),
                        ([260,261,262].map { (350,$0) })]
            for gap in gaps {
                for (index,point) in gap.enumerated() {
                    let c = try XCTUnwrap(rendered.colorAt(x: point.0,y: point.1)?.usingColorSpace(.deviceRGB))
                    if index == 1 {
                        XCTAssertGreaterThan(c.redComponent, 0.8, "Orange at \(point)")
                        XCTAssertLessThan(c.blueComponent, 0.2, "Orange at \(point)")
                        XCTAssertGreaterThan(c.greenComponent, 0.4, "Orange at \(point)")
                        XCTAssertLessThan(c.greenComponent, 0.8, "Orange at \(point)")
                    } else {
                        XCTAssertLessThan(c.redComponent+c.greenComponent+c.blueComponent, 0.1, "Black at \(point)")
                    }
                }
            }
        }
    }

    func testLandmarkArtworkUsesItsOwnSourcePanelOrigin() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1)
        trip.phase = .landmark
        let renderer = ImageRenderer(content: OriginalTrailView(game: game, trip: trip))
        renderer.scale = 1
        let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        // Check only black ink: SwiftUI's isolated and composited image paths
        // can convert colored palette entries differently. Display RGB parity
        // is separate from this source-artwork placement regression.
        let artwork = ImageRenderer(content: PixelArtwork(resource: trip.location.image, frame: trip.location.frame)
            .frame(width: 262, height: 155))
        artwork.scale = 1
        let source = NSBitmapImageRep(cgImage: try XCTUnwrap(artwork.cgImage))
        XCTAssertEqual(source.pixelsWide, 262)
        XCTAssertEqual(source.pixelsHigh, 155)
        // Rect4=(top9,left64,bottom164,right326), independently of pane13.
        var differences = 0
        var onePixelShiftDifferences = 0
        var examples: [String] = []
        for y in 0..<155 {
            for x in 0..<262 {
                let a = try XCTUnwrap(source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(rendered.colorAt(x: 64+x, y: 9+y)?.usingColorSpace(.deviceRGB))
                let shifted = try XCTUnwrap(rendered.colorAt(x: 63+x, y: 9+y)?.usingColorSpace(.deviceRGB))
                let sourceBlack = a.redComponent+a.greenComponent+a.blueComponent < 0.01
                if sourceBlack != (shifted.redComponent+shifted.greenComponent+shifted.blueComponent < 0.01) {
                    onePixelShiftDifferences += 1
                }
                if sourceBlack != (b.redComponent+b.greenComponent+b.blueComponent < 0.01) {
                    differences += 1
                    if examples.count < 8 { examples.append("(\(x),\(y)): \(a) vs \(b)") }
                }
            }
        }
        XCTAssertEqual(differences, 0, "Landmark artwork must retain source pixels at the original root position: \(examples)")
        XCTAssertGreaterThan(onePixelShiftDifferences, 0, "The original artwork must distinguish a one-pixel translation")
    }

    func testTrailJournalKeepsItsAbsoluteSourceFrame() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        var trip = Journey(seed: 1)
        trip.phase = .landmark
        let renderer = ImageRenderer(content: OriginalTrailView(game: game, trip: trip))
        renderer.scale = 1
        let rendered = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        // CODE14 rectangle6 is (64,211,262,102). CODE5 adds a black
        // one-pixel inner frame and orange outer frame, independent of pane13.
        for y in [210, 313] {
            let c = try XCTUnwrap(rendered.colorAt(x: 100, y: y)?.usingColorSpace(.deviceRGB))
            XCTAssertLessThan(c.redComponent + c.greenComponent + c.blueComponent, 0.1,
                              "Journal black edge must remain at original window y\(y)")
        }
        for y in [209, 314] {
            let c = try XCTUnwrap(rendered.colorAt(x: 100, y: y)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(c.redComponent, 0.8)
            XCTAssertLessThan(c.blueComponent, 0.2)
            XCTAssertGreaterThan(c.greenComponent, 0.4)
            XCTAssertLessThan(c.greenComponent, 0.8)
        }
    }

    func testFrameAndRegistrationControlsMatchOriginalCapturedInk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let game = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 1))
        let url = try GameDataTestSupport.referenceCapture(
            named: "original-registration", withExtension: "png")
        let original = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let renderer = ImageRenderer(content: OriginalRegistrationView(game: game))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rendered = NSBitmapImageRep(cgImage: image)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 322)
        func ink(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> Bool {
            let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return c.redComponent + c.greenComponent + c.blueComponent < 1.5
        }
        // Root(384,218) is independently established by the complete top and
        // bottom artwork strips. Source pane origin(9,9) gives content(393,227).
        // The former y219 crop compensated for a native inner y8 mistake and
        // could not prove root-frame alignment.
        func compare(_ name: String, left: Int, top: Int, width: Int, height: Int,
                     include: (Int,Int) -> Bool = { _,_ in true }) throws {
            var mismatches: [String] = []
            for y in top..<top+height {
                for x in left..<left+width where include(x,y) {
                    if try ink(rendered,x,y) != ink(original,384+x,218+y) {
                        mismatches.append("(\(x),\(y))")
                    }
                }
            }
            XCTAssertTrue(mismatches.isEmpty,
                          "\(name): \(mismatches.count) differing ink pixels; first: \(mismatches.prefix(12))")
        }
        try compare("top frame",left:7,top:0,width:498,height:7)
        try compare("bottom frame",left:7,top:315,width:498,height:7)
        try compare("left frame",left:0,top:0,width:7,height:322)
        try compare("right frame",left:505,top:0,width:7,height:322)
        try compare("main pane frame",left:7,top:7,width:498,height:308) { x,y in
            x < 9 || x > 502 || y < 9 || y > 312
        }
        // DITL9020 item8 embeds9022 at(31,116); radio1(15,15), pitch20.
        for row in 0..<8 {
            try compare("occupation \(row)",left:55,top:140+row*20,width:115,height:20)
        }
        // Heading item12 covers the top group edge at pane x84...174.
        try compare("group",left:35,top:125,width:201,height:183) { x,y in
            (x == 35 || x == 235 || y == 125 || y == 307) && !(y == 125 && (93..<184).contains(x))
        }
        try compare("name label",left:171,top:44,width:47,height:18)
        try compare("occupation heading",left:93,top:120,width:91,height:18)
        try compare("companions heading",left:262,top:134,width:232,height:20)
        try compare("OK",left:334,top:272,width:80,height:20)
        let fields = [(218,41)] + (0..<4).map { (310,162+$0*20) }
        for (index,rect) in fields.enumerated() {
            let (left,top) = rect
            try compare("field border \(index)",left:left,top:top,width:127,height:21) { x,y in
                x == left || x == left+126 || y == top || y == top+20
            }
        }
        let attachment = XCTAttachment(image: NSImage(cgImage: image, size: .init(width:512,height:322)))
        attachment.name = "Registration content at original scale"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
