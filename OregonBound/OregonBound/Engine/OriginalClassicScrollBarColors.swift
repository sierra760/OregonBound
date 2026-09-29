/// Requested RGB values from System7 CDEF1. Device Color2Index/CLUT conversion
/// happens after these calculations and is intentionally not simulated here.
enum OriginalClassicScrollBarColors {
    struct RGB16: Equatable {
        var red: UInt16
        var green: UInt16
        var blue: UInt16
        var rgba8: [UInt8] { [UInt8(red >> 8), UInt8(green >> 8), UInt8(blue >> 8), 255] }
    }

    // CDEF1:0cd2–0d2b fallback table; matching System cctb0 entries0...14.
    private static let bases: [RGB16] = [
        .init(red: 0, green: 0, blue: 0), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 0, green: 0, blue: 0), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 21845, green: 21845, blue: 21845), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 0, green: 0, blue: 0), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 0, green: 0, blue: 0), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 0, green: 0, blue: 0), .init(red: 65535, green: 65535, blue: 65535),
        .init(red: 0, green: 0, blue: 0), .init(red: 52428, green: 52428, blue: 65535),
        .init(red: 13107, green: 13107, blue: 26214)
    ]
    // CDEF1:0d2c–0daf, derived entries16...37 (entry15 is unused).
    private static let recipes: [(Int, Int, Int)] = [
        (7,8,0),(7,8,1),(7,8,5),(7,8,10),(7,8,13),
        (5,6,0),(5,6,2),(5,6,5),(5,6,10),(5,6,13),
        (9,10,0),(9,10,5),(9,10,8),(9,10,10),(9,10,13),
        (11,12,0),(11,12,1),(11,12,2),
        (13,14,0),(13,14,4),(13,14,10),(13,14,15)
    ]
    static let trackPattern: [UInt8] = [0x88,0x22,0x88,0x22,0x88,0x22,0x88,0x22]
    static let gamePaper = RGB16(red: 0xff00, green: 0xf66d, blue: 0x8997)

    /// CDEF1:09d4–0a2c uses actual AuxCtl entries if present, otherwise fallback.
    /// Passing overrides is explicit: the game's cctb0 is not a captured live table.
    static func color(_ index: Int, overrides: [Int: RGB16] = [:]) -> RGB16 {
        precondition((0..<15).contains(index) || (16..<38).contains(index))
        if index < 16 { return overrides[index] ?? bases[index] }
        let (a,b,weight) = recipes[index-16]
        let first = overrides[a] ?? bases[a], second = overrides[b] ?? bases[b]
        return RGB16(red: mix(first.red,second.red,weight), green: mix(first.green,second.green,weight),
                     blue: mix(first.blue,second.blue,weight))
    }

    /// CDEF1:0862–08d2 probes the ACTUAL device's Color2Index mapping. Color
    /// drawing requires depth>=4 and distinct adjacent shades in all three
    /// groups. Do not guess this result from resource palette proximity.
    static func usesColor(pixelDepth: Int, overrides: [Int: RGB16] = [:],
                          colorToIndex: (RGB16) -> UInt32) -> Bool {
        guard pixelDepth >= 4 else { return false }
        for group in [26...30,31...33,34...37] {
            var previous: UInt32 = 0x63736420 // Literal initial D4 at08aa.
            for index in group {
                let mapped = colorToIndex(color(index,overrides: overrides))
                if mapped == previous { return false }
                previous = mapped
            }
        }
        return true
    }

    /// Original track pattern is aligned to QuickDraw PORT coordinates, not
    /// individually restarted at the top of each track piece: CDEF1:06e8–0734.
    static func trackColor(x: Int, y: Int, overrides: [Int: RGB16] = [:]) -> RGB16 {
        let bit = trackPattern[y & 7] & (0x80 >> (x & 7)) != 0
        return color(bit ? 28 : 22, overrides: overrides)
    }

    /// CDEF1:0826–085a restores the sign AFTER taking the unsigned product's
    /// high16bits. In particular weight15 can stop one RGB16 unit short.
    private static func mix(_ a: UInt16, _ b: UInt16, _ weight: Int) -> UInt16 {
        let delta = Int(b) - Int(a)
        let amount = (abs(delta) * weight * 0x1111) >> 16
        return UInt16(Int(a) + (delta < 0 ? -amount : amount))
    }
}
