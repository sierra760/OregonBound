import Foundation

/// Original unsigned8 mono PCM with the resource's exact unsigned16.16 sample rate.
struct OriginalSoundSample {
    let samples: [UInt8]
    let sampleRate: Double

    /// Prepared imports preserve the original SoundHeader rate independently
    /// of the integer rate in RIFF. The resource ID does not define PCM format.
    init?(record: SoundExtractor.Record, wav: Data) {
        self.init(wav: wav, sampleCount: record.sampleCount, fixedRate: record.fixedSampleRate,
                  validateRoundedRate: true)
    }

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
        self.init(wav: wav, sampleCount: metadata.count, fixedRate: metadata.rate,
                  validateRoundedRate: false)
    }

    private init?(wav: Data, sampleCount: Int, fixedRate: UInt32, validateRoundedRate: Bool) {
        let roundedRate = Int((Double(fixedRate) / 65536).rounded(.toNearestOrEven))
        guard sampleCount > 0, roundedRate > 0 else { return nil }
        let data = Array(wav)
        guard data.count >= 12, Array(data[0..<4]) == Array("RIFF".utf8),
              Array(data[8..<12]) == Array("WAVE".utf8) else { return nil }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset+1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset+2) << 16 }
        guard u32(4) == data.count - 8 else { return nil }
        var offset = 12
        var validFormat = false
        var pcm: [UInt8]?
        while offset < data.count {
            guard offset + 8 <= data.count else { return nil }
            let kind = Array(data[offset..<offset+4])
            let count = u32(offset+4)
            offset += 8
            guard count <= data.count-offset else { return nil }
            if kind == Array("fmt ".utf8) {
                guard !validFormat, count >= 16, u16(offset) == 1, u16(offset+2) == 1,
                      u16(offset+12) == 1, u16(offset+14) == 8 else { return nil }
                if validateRoundedRate && (u32(offset+4) != roundedRate || u32(offset+8) != roundedRate) { return nil }
                validFormat = true
            } else if kind == Array("data".utf8) {
                guard pcm == nil, count == sampleCount else { return nil }
                pcm = Array(data[offset..<offset+count])
            }
            offset += count
            // Our reference WAV writer omits final odd-byte padding. Interior
            // chunks still need alignment before their following chunk header.
            if offset < data.count && count & 1 != 0 { offset += 1 }
        }
        guard validFormat, let pcm, pcm.count == sampleCount else { return nil }
        samples = pcm
        sampleRate = Double(fixedRate)/65536
    }
}
