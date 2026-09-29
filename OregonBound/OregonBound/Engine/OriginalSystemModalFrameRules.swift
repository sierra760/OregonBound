/// Nonmovable dBoxProc (procID1), recovered from System7 WDEF0.
/// RGB values are requests to Color QuickDraw, before device CLUT conversion.
enum OriginalSystemModalFrameRules {
    struct RGB16: Equatable {
        var red: UInt16
        var green: UInt16
        var blue: UInt16
        var rgba8: [UInt8] { [UInt8(red >> 8), UInt8(green >> 8), UInt8(blue >> 8), 255] }
    }
    struct Fill: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var colorIndex: Int
    }
    static let extent = 8 // WDEF0:0728–074c, inset−1 then inset−7.
    private static let bases: [RGB16] = [
        .init(red:65535,green:65535,blue:65535), .init(red:0,green:0,blue:0),
        .init(red:0,green:0,blue:0), .init(red:0,green:0,blue:0),
        .init(red:65535,green:65535,blue:65535), .init(red:65535,green:65535,blue:65535),
        .init(red:0,green:0,blue:0), .init(red:65535,green:65535,blue:65535),
        .init(red:0,green:0,blue:0), .init(red:52428,green:52428,blue:65535),
        .init(red:0,green:0,blue:0), .init(red:52428,green:52428,blue:65535),
        .init(red:13107,green:13107,blue:26214)
    ]
    // WDEF0:0e26. Entries16...36; System wctb0 matches fallback0...12.
    private static let recipes: [(Int,Int,Int)] = [
        (5,6,0),(5,6,7),(5,6,8),(5,6,10),(5,6,13),
        (7,8,0),(7,8,1),(7,8,4),(9,10,0),(9,10,4),(9,10,6),(9,10,11),(9,10,15),
        (0,0,0),(9,10,0),(9,10,4),(9,10,6),(9,10,11),(11,8,0),(11,12,4),(7,12,15)
    ]
    /// WDEF0:0cc6–0d34 searches actual AuxWin before wctb0/fallback.
    /// This port supplies the recovered defaults unless an actual base entry is supplied.
    static func color(_ index: Int, windowColors: [Int: RGB16] = [:]) -> RGB16 {
        precondition((0...12).contains(index) || (16...36).contains(index))
        if index < 16 { return windowColors[index] ?? bases[index] }
        let (a,b,w) = recipes[index-16]
        let first = windowColors[a] ?? bases[a], second = windowColors[b] ?? bases[b]
        func mix(_ x: UInt16, _ y: UInt16) -> UInt16 {
            let delta = Int(y)-Int(x)
            let amount = (abs(delta)*w*0x1111) >> 16 // WDEF0:0b8c; unsigned high word.
            return UInt16(Int(x)+(delta < 0 ? -amount : amount))
        }
        return .init(red:mix(first.red,second.red),green:mix(first.green,second.green),blue:mix(first.blue,second.blue))
    }
    /// WDEF0:0bc8–0c50. No nearest-palette heuristic: mapping must come from the device.
    static func usesColor(pixelDepth: Int, windowColors: [Int: RGB16] = [:],
                          colorToIndex: (RGB16) -> UInt32) -> Bool {
        guard pixelDepth >= 2 else { return false }
        for group in [16...20,21...23,34...35,24...28] {
            var previous: UInt32 = 0x63736420
            for index in group {
                let mapped = colorToIndex(color(index,windowColors:windowColors))
                guard mapped != previous else { return false }
                previous = mapped
            }
        }
        return true
    }
    /// Integer filled rectangles in drawing order; the content region is untouched.
    static func fills(contentWidth: Int, contentHeight: Int, active: Bool = true) -> [Fill] {
        precondition(contentWidth > 0 && contentHeight > 0)
        let width = contentWidth+16, height = contentHeight+16
        var result: [Fill] = []
        func fill(_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: Int) {
            result.append(.init(x:x,y:y,width:w,height:h,colorIndex:color))
        }
        func ring(_ inset: Int,_ thickness: Int,_ color: Int) {
            let w = width-2*inset, h = height-2*inset
            fill(inset,inset,w,thickness,color)
            fill(inset,inset+h-thickness,w,thickness,color)
            fill(inset,inset+thickness,thickness,h-2*thickness,color)
            fill(inset+w-thickness,inset+thickness,thickness,h-2*thickness,color)
        }
        // WDEF0:059e–060a: corner color C, top/left B, right/bottom A.
        // Caller pushes A,B,C; separate word pushes make a packed (v,h) Point.
        func bevel(_ inset: Int,_ a: Int,_ b: Int,_ c: Int) {
            let right = width-inset-1, bottom = height-inset-1
            fill(inset,inset,right-inset,1,b)
            fill(inset,inset+1,1,bottom-inset-1,b)
            fill(right,inset,1,1,c)
            fill(inset,bottom,1,1,c)
            fill(right,inset+1,1,bottom-inset,a)
            fill(inset+1,bottom,right-inset-1,1,a)
        }
        // 0262/0266: inactive immediate $13 is decimal19, not base entry13.
        ring(0,1,active ? 1 : 19) // d4=0 means no shadow.
        if active { // 02e4; active table0ea6.
            bevel(1,26,24,26)
            ring(2,1,23)
            bevel(3,30,32,32)
            ring(4,1,28)
        } else { // 02d2; inactive table0eb6. Color branch retains solid pen.
            bevel(1,21,21,21)
            ring(2,1,21)
            bevel(3,18,18,18)
            ring(4,1,18)
        }
        ring(5,3,0)       // 032c–033e: white pen pattern writes background color0.
        return result
    }
}
