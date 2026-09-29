import Testing
@testable import OregonBound

struct OriginalSystemRadioRulesTests {
    typealias R = OriginalSystemRadioRules
    @Test func authoredBoundsPlaceRingAndLabelWithAsymmetricOddHeightRounding() {
        #expect(R.markerRect(control:.init(x:70,y:50,width:75,height:15)) == .init(x:72,y:52,width:12,height:12))
        #expect(R.markerRect(control:.init(x:70,y:70,width:75,height:15)) == .init(x:72,y:72,width:12,height:12))
        #expect(R.markerRect(control:.init(x:0,y:0,width:75,height:16)) == .init(x:2,y:2,width:12,height:12))
        #expect(R.markerRect(control:.init(x:0,y:0,width:75,height:15),rightToLeft:true) == .init(x:61,y:2,width:12,height:12))
        #expect(R.labelX == 18 && R.labelBaseline() == 12)
        #expect(R.labelBaseline(controlHeight:20) == 14)
        #expect(R.labelBaseline(controlHeight:32,lineCount:2) == 28)
    }
    @Test func incrementalFixedPointCirclesMatchIndependentIntegerQuadratic() {
        // For square ovals FixRatio=1.0 exactly. Independently solve the
        // integer squared radius; no floating-point ellipse or same loop.
        for size in 1...12 {
            let spans = R.filledCircleSpans(size:size,x:7,y:9)
            for row in 0..<size {
                let v = 1-size+2*row
                let square = size*size-v*v
                let k = (0...size).last { $0*$0 <= square }!
                let left = (size-k)/2, right = (size+k+1)/2
                #expect(spans.first(where:{$0.y == 9+row}) == .init(x:7+left,y:9+row,width:right-left))
            }
        }
        #expect(R.filledCircleSpans(size:12).map(\.width) == [4,8,10,10,12,12,12,12,10,10,8,4])
        #expect(R.filledCircleSpans(size:6).map(\.width) == [4,6,6,6,6,4])
    }
    @Test func selectionAddsSixPixelOvalWithoutChangingNormalRing() {
        let normal = pixels(R.markerSpans(state:.init(selected:false)))
        let selected = pixels(R.markerSpans(state:.init(selected:true)))
        let dot = pixels(R.filledCircleSpans(size:6,x:5,y:5))
        #expect(selected == normal.union(dot))
        #expect(normal.intersection(dot).isEmpty)
        #expect(dot.count == 32)
        #expect(normal.count == 32)
    }
    @Test func pressedOnlyThickensRingAndDisabledRetainsNormalMarker() {
        let normal = pixels(R.markerSpans(state:.init(selected:false)))
        let pressed = pixels(R.markerSpans(state:.init(selected:false,highlight:11)))
        #expect(normal.isSubset(of:pressed))
        #expect(pressed.count == 60)
        for highlight: UInt8 in [254,255] {
            #expect(R.markerSpans(state:.init(selected:true,highlight:highlight)) == R.markerSpans(state:.init(selected:true)))
            #expect(R.State(selected:true,highlight:highlight).labelTreatment == .eraseGrayPatternInsideControl)
            #expect(R.State(selected:true,highlight:highlight,colorGrafPort:true).labelTreatment == .grayishTextOr)
        }
        #expect(R.State(selected:true,highlight:11).labelTreatment == .normal)
    }
    private func pixels(_ spans:[R.Span]) -> Set<Int> {
        Set(spans.flatMap { span in (span.x..<span.x+span.width).map { span.y*100+$0 } })
    }
}
