import Testing
@testable import OregonBound

struct OriginalSystemPushButtonRulesTests {
    typealias R = OriginalSystemPushButtonRules
    @Test func normalButtonUsesOriginalTenPixelOvalAndOnePixelInnerFrame() {
        let body=R.body(width:80,height:20)
        #expect(body.map(\.x) == [3,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,3])
        let all=pixels(body),inner=pixels(R.filledRoundRect(.init(x:1,y:1,width:78,height:18),ovalDiameter:8))
        #expect(pixels(R.outline(width:80,height:20)) == all.subtracting(inner))
        #expect(body.count == 20)
    }
    @Test func defaultRingIsOutsetFourPenThreeWithOnePixelSeparation() {
        let button=R.Rect(x:0,y:0,width:80,height:20)
        let outer=pixels(R.filledRoundRect(button.inset(-4),ovalDiameter:16))
        let inner=pixels(R.filledRoundRect(button.inset(-1),ovalDiameter:10))
        let ring=pixels(R.defaultRing(width:80,height:20))
        #expect(ring == outer.subtracting(inner))
        #expect(ring.intersection(pixels(R.body(width:80,height:20))).isEmpty)
        #expect(R.defaultRing(width:80,height:20).map(\.y).min() == -4)
        #expect(R.defaultRing(width:80,height:20).map(\.y).max() == 23)
    }
    @Test func integerLabelsUseFloorCenterAndOriginalBaseline() {
        // Chicago widths: Cancel43, OK17. Half-pixel SwiftUI centers are wrong.
        #expect(R.labelOrigins(width:80,height:20,lineWidths:[43]) == [.init(x:18,y:2)])
        #expect(R.labelOrigins(width:80,height:20,lineWidths:[17]) == [.init(x:31,y:2)])
        #expect(R.labelOrigins(width:60,height:20,lineWidths:[71]) == [.init(x:-6,y:2)])
        #expect(R.labelOrigins(width:80,height:40,lineWidths:[43,17]) == [.init(x:18,y:4),.init(x:31,y:20)])
    }
    @Test func pressedColorsSwapBodyAndTextRolesButKeepFrameBlack() {
        #expect(R.colors(pressed:false) == .init(bodyEntry:1,labelEntry:2,frameEntry:0))
        #expect(R.colors(pressed:true) == .init(bodyEntry:2,labelEntry:1,frameEntry:0))
        // Both enabled states have identical masks, including the default ring.
        #expect(R.colors(pressed:false).frameEntry == R.colors(pressed:true).frameEntry)
    }
    @Test func straightSidesExtendWithoutAdvancingCornerRaster() {
        for diameter in [7,8,10,16] {
            let square=R.filledRoundRect(.init(x:0,y:0,width:diameter,height:diameter),ovalDiameter:diameter)
            let extended=R.filledRoundRect(.init(x:0,y:0,width:80,height:40),ovalDiameter:diameter)
            let top=diameter/2,bottomStart=40-diameter+top
            for y in 0..<40 {
                let sourceY=y<top ? y : y>=bottomStart ? diameter-(40-y) : top-1
                #expect(extended[y].x == square[sourceY].x)
                #expect(extended[y].width == square[sourceY].width+80-diameter)
            }
        }
    }
    private func pixels(_ spans:[R.Span]) -> Set<String> {
        Set(spans.flatMap { s in (s.x..<s.x+s.width).map { "\($0),\(s.y)" } })
    }
}

#if os(macOS)
import SwiftUI
import CoreGraphics

@Suite(.enabled(if: GameData.isReady))
struct OriginalSystemPushButtonRenderingTests {
    /// Whole-label inversion used to turn the outline/default ring white. This
    /// exercises actual Canvas/image-mask rendering, not just color-role data.
    @Test @MainActor func pressingChangesOnlyBodyAndLabelPixels() throws {
        _ = try #require(BitmapFont.chicago12)
        for title in ["Cancel","OK"] {
            let normal=try ink(title:title,pressed:false)
            let pressed=try ink(title:title,pressed:true)
            typealias R = OriginalSystemPushButtonRules
            func mask(_ spans:[R.Span]) -> Set<Int> {
                Set(spans.flatMap { s in (s.x..<s.x+s.width).map { (s.y+4)*88+$0+4 } })
            }
            let frame=mask(R.outline(width:80,height:20)).union(mask(R.defaultRing(width:80,height:20)))
            let body=mask(R.body(width:80,height:20))
            let label=normal.subtracting(frame)
            #expect(!label.isEmpty)
            #expect(label.isSubset(of:body))
            #expect(pressed == body.subtracting(label).union(frame))
            #expect(frame.isSubset(of:normal) && frame.isSubset(of:pressed))
        }
    }
    @Test @MainActor func yellowPressedLabelUsesBodyColorWithoutInvertingRingOrPaper() throws {
        let paper=Color(red:1,green:246.0/255,blue:137.0/255)
        let normal=try rgb(title:"OK",pressed:false,paper:paper)
        let pressed=try rgb(title:"OK",pressed:true,paper:paper)
        typealias R=OriginalSystemPushButtonRules
        func mask(_ spans:[R.Span]) -> Set<Int> {
            Set(spans.flatMap { s in (s.x..<s.x+s.width).map { (s.y+4)*88+$0+4 } })
        }
        let frame=mask(R.outline(width:80,height:20)).union(mask(R.defaultRing(width:80,height:20)))
        let body=mask(R.body(width:80,height:20))
        let requestedBody=normal[14*88+6]
        #expect(requestedBody != 0 && requestedBody != 0xffffff)
        for pixel in normal.indices {
            let expected = frame.contains(pixel) ? 0 : body.contains(pixel) ? (normal[pixel] == 0 ? requestedBody : 0) : normal[pixel]
            #expect(pressed[pixel] == expected)
        }
    }
    @MainActor private func ink(title:String,pressed:Bool) throws -> Set<Int> {
        let values=try rgb(title:title,pressed:pressed,paper:.white)
        return Set(values.indices.filter { values[$0] == 0 })
    }
    @MainActor private func rgb(title:String,pressed:Bool,paper:Color) throws -> [Int] {
        let renderer=ImageRenderer(content:OriginalSystemPushButtonArtwork(title:title,isDefault:true,paper:paper,pressed:pressed)
            .frame(width:80,height:20).padding(4).background(.white))
        renderer.scale=1
        let image=try #require(renderer.cgImage)
        #expect(image.width == 88 && image.height == 28)
        let context=try #require(CGContext(data:nil,width:88,height:28,bitsPerComponent:8,bytesPerRow:88*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image,in:CGRect(x:0,y:0,width:88,height:28))
        let bytes=try #require(context.data?.assumingMemoryBound(to:UInt8.self))
        return (0..<(88*28)).map { (Int(bytes[$0*4])<<16)|(Int(bytes[$0*4+1])<<8)|Int(bytes[$0*4+2]) }
    }
}
#endif
