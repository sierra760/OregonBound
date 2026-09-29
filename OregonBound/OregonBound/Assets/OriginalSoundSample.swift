import Foundation

/// Original unsigned8 mono PCM with the resource's exact unsigned16.16 sample rate.
struct OriginalSoundSample {
    let samples: [UInt8]
    let sampleRate: Double

    init?(resource: Int, wav: Data) {
        let metadata: (count: Int, rate: UInt32)
        switch resource {
        case 9001: metadata = (10226,486157963)
        case 9002: metadata = (3664,729236945)
        case 9003: metadata = (967,729236945)
        case 9004: metadata = (388,729236945)
        case 9006: metadata = (3919,364618472)
        case 9007: metadata = (1024,729236945)
        default: return nil
        }
        let data = Array(wav)
        guard data.count >= 12, Array(data[0..<4]) == Array("RIFF".utf8),
              Array(data[8..<12]) == Array("WAVE".utf8) else { return nil }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset+1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset+2) << 16 }
        var offset = 12
        var validFormat = false
        var pcm: [UInt8]?
        while offset+8 <= data.count {
            let kind = Array(data[offset..<offset+4])
            let count = u32(offset+4)
            offset += 8
            guard count <= data.count-offset else { return nil }
            if kind == Array("fmt ".utf8) {
                guard count >= 16 else { return nil }
                validFormat = u16(offset) == 1 && u16(offset+2) == 1 && u16(offset+12) == 1 && u16(offset+14) == 8
            } else if kind == Array("data".utf8) {
                pcm = Array(data[offset..<offset+count])
            }
            offset += count+(count & 1)
        }
        guard validFormat, let pcm, pcm.count == metadata.count else { return nil }
        samples = pcm
        sampleRate = Double(metadata.rate)/65536
    }
}
