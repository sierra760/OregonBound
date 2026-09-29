import Foundation

/// CODE13:0480 sets30 ticks before timer event6 switches DITL9161 to9160.
struct OriginalHuntPreparation {
    private var timer = OriginalDialogTimer(ticks: 30)
    var remainingTicks: Int { timer.remainingTicks }
    var isReady: Bool { timer.isFinished }
    mutating func advance(to tick: Int, active: Bool) {
        timer.advance(to: tick, active: active)
    }
}

/// CURS128: two16×16 one-bit planes followed by hotspot(v:7,h:7).
enum OriginalHuntCursor {
    static var resource: Data? {
        guard let url = GameData.url(forResource: "curs_128", withExtension: "bin", subdirectory: "runtime") else { return nil }
        return try? Data(contentsOf: url)
    }
    static var rgba: [UInt8] { decode(resource ?? Data()) }
    static func decode(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        guard bytes.count == 68 else { return [UInt8](repeating: 0, count: 1024) }
        return (0..<256).flatMap { index -> [UInt8] in
            let bit = UInt8(0x80 >> (index%8))
            guard bytes[32+index/8] & bit != 0 else { return [0,0,0,0] }
            let value: UInt8 = bytes[index/8] & bit == 0 ? 255 : 0
            return [value,value,value,255]
        }
    }
    static let hotspotX = 7
    static let hotspotY = 7
}
