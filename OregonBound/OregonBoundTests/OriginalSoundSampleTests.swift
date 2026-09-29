import Foundation
import Testing
@testable import OregonBound

struct OriginalSoundSampleTests {
    private func wav(samples: [UInt8]) -> Data {
        var data = Data("RIFF".utf8)
        func word(_ value: UInt32) { data += withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        word(UInt32(36+samples.count));data += Data("WAVEfmt ".utf8);word(16)
        data += [1,0,1,0];word(11127);word(11127);data += [1,0,8,0]
        data += Data("data".utf8);word(UInt32(samples.count));data += samples
        return data
    }
    @Test func originalFractionalRateReplacesRoundedWaveRateWithoutChangingPCM() throws {
        let bytes = (0..<3664).map { UInt8($0%256) }
        let sample = try #require(OriginalSoundSample(resource: 9002,wav: wav(samples: bytes)))
        #expect(sample.sampleRate == 729236945.0/65536)
        #expect(sample.samples == bytes)
    }
    @Test func unexpectedFormatAndTruncatedSoundAreRejected() {
        #expect(OriginalSoundSample(resource: 9002,wav: wav(samples: [128])) == nil)
        #expect(OriginalSoundSample(resource: 9999,wav: wav(samples: [])) == nil)
        var data = wav(samples: Array(repeating: 128,count: 1024));data[22] = 2
        #expect(OriginalSoundSample(resource: 9007,wav: data) == nil)
    }
}
