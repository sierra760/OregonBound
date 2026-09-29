import XCTest
@testable import OregonBound

final class OriginalSystemModalFrameRulesTests: XCTestCase {
    typealias Rules = OriginalSystemModalFrameRules
    func index(x: Int, y: Int, width: Int = 300, height: Int = 125) -> Int? {
        Rules.fills(contentWidth: width,contentHeight: height).last {
            x >= $0.x && x < $0.x+$0.width && y >= $0.y && y < $0.y+$0.height
        }?.colorIndex
    }
    func testWDEF0728And074cExpandEightWithoutPaintingContent() {
        for y in 0..<141 { for x in 0..<316 {
            let interior = (8..<308).contains(x) && (8..<133).contains(y)
            XCTAssertEqual(index(x:x,y:y) == nil, interior, "pixel \(x),\(y)")
        }}
        XCTAssertNil(index(x:316,y:140))
        XCTAssertNil(index(x:315,y:141))
    }
    func testWDEF059eBevelCornerEndpoints() {
        // Unlike a rounded or gradient stroke, these corners have explicit colors.
        XCTAssertEqual(index(x:1,y:1),24)
        XCTAssertEqual(index(x:314,y:1),26)
        XCTAssertEqual(index(x:1,y:139),26)
        XCTAssertEqual(index(x:314,y:139),26)
        XCTAssertEqual(index(x:3,y:3),32)
        XCTAssertEqual(index(x:312,y:3),32)
        XCTAssertEqual(index(x:3,y:137),32)
        XCTAssertEqual(index(x:312,y:137),30)
    }
    func testWDEF0ea6ActiveBandsAndWhitePattern() {
        XCTAssertEqual((0..<8).map { index(x:150,y:$0)! },[1,24,23,32,28,0,0,0])
        XCTAssertEqual((0..<8).map { index(x:315-$0,y:70)! },[1,26,23,30,28,0,0,0])
        let fills = Rules.fills(contentWidth:1,contentHeight:1)
        XCTAssertTrue(fills.allSatisfy { $0.width > 0 && $0.height > 0 })
    }
    func testWDEF0b8cUnsignedMultiplyHighWordAndWindowOverride() {
        XCTAssertEqual(Rules.color(24).rgba8,[204,204,255,255])
        XCTAssertEqual(Rules.color(26).rgba8,[122,122,153,255])
        XCTAssertEqual(Rules.color(28),.init(red:1,green:1,blue:1))
        XCTAssertEqual(Rules.color(23).rgba8,[187,187,187,255])
        let red = Rules.RGB16(red:65535,green:0,blue:0)
        XCTAssertEqual(Rules.color(24,windowColors:[9:red]),red)
        XCTAssertEqual(Rules.color(0,windowColors:[0:red]),red)
    }
    func testWDEF0bc8DeviceDepthAndActualMappingAreRequired() {
        func unique(_ color: Rules.RGB16) -> UInt32 {
            UInt32(color.red)<<16 | UInt32(color.blue)
        }
        XCTAssertFalse(Rules.usesColor(pixelDepth:1,colorToIndex:unique))
        XCTAssertTrue(Rules.usesColor(pixelDepth:2,colorToIndex:unique))
        XCTAssertFalse(Rules.usesColor(pixelDepth:8,colorToIndex:{ _ in 0 }))
    }
    func testInactiveWDEF0266And0eb6ColorsAndGeometry() {
        let active = Rules.fills(contentWidth:300,contentHeight:125)
        let inactive = Rules.fills(contentWidth:300,contentHeight:125,active:false)
        // Hilite changes color only; the content stays in exactly the same place.
        XCTAssertEqual(active.count,inactive.count)
        for (a,b) in zip(active,inactive) {
            XCTAssertEqual([a.x,a.y,a.width,a.height],[b.x,b.y,b.width,b.height])
        }
        func inactiveIndex(_ x: Int,_ y: Int) -> Int? {
            inactive.last { x >= $0.x && x < $0.x+$0.width && y >= $0.y && y < $0.y+$0.height }?.colorIndex
        }
        XCTAssertEqual((0..<8).map { inactiveIndex(150,$0)! },[19,21,21,18,18,0,0,0])
        XCTAssertEqual((0..<8).map { inactiveIndex(315-$0,70)! },[19,21,21,18,18,0,0,0])
        XCTAssertEqual(inactiveIndex(1,1),21)
        XCTAssertEqual(inactiveIndex(314,139),21)
        XCTAssertEqual(inactiveIndex(3,137),18)
        XCTAssertNil(inactiveIndex(8,8))
        XCTAssertEqual(Rules.color(19).rgba8,[85,85,85,255])
        XCTAssertEqual(Rules.color(21).rgba8,[255,255,255,255])
        XCTAssertEqual(Rules.color(18).rgba8,[119,119,119,255])
    }

}
