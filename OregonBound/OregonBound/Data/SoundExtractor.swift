import Foundation

/// Converts the game's format-1 'snd ' resources (stdSH 8-bit unsigned mono
/// PCM) into sounds/snd_<id>.wav, byte-identical to Python's `wave` module output.
///
/// Port of scripts/extract_snd.py.
enum SoundExtractor {
    enum Failure: Error, CustomStringConvertible {
        case tooShort(id: Int)
        case unsupportedFormat(id: Int, format: Int)
        case truncatedCommands(id: Int)
        case noBufferCommand(id: Int)
        case pointerCommand(id: Int)
        case truncatedHeader(id: Int, offset: Int, length: Int)
        case unsupportedEncoding(id: Int, encode: Int)

        var description: String {
            switch self {
            case .tooShort(let id): return "Sound \(id): snd resource too short"
            case .unsupportedFormat(let id, let format):
                return String(format: "Sound %d: unsupported snd format 0x%04x (only format 1 is supported)", id, format)
            case .truncatedCommands(let id): return "Sound \(id): snd command list is truncated"
            case .noBufferCommand(let id): return "Sound \(id): no sampled-sound command found in snd resource"
            case .pointerCommand(let id): return "Sound \(id): sample command must use a resource offset, not a pointer"
            case .truncatedHeader(let id, let offset, let length):
                return "Sound \(id): SoundHeader at \(offset) truncated (resource length=\(length))"
            case .unsupportedEncoding(let id, let encode):
                return String(format: "Sound %d: unsupported SoundHeader encoding 0x%02x (only stdSH=0x00 is supported)", id, encode)
            }
        }
    }

    struct Sound {
        let sampleRate: Int
        let bitsPerSample: Int
        let pcm: Data
        /// True when the header's declared length exceeded the resource and the
        /// samples were truncated to what was present (the reference prints a warning).
        let truncated: Bool
    }

    /// Parses a format-1 snd resource: synth list, command list, then the stdSH
    /// SoundHeader referenced by the first offset-based soundCmd or bufferCmd.
    static func parseFormat1(_ data: Data, resourceID id: Int = 0) throws -> Sound {
        let reader = BinaryReader(data)
        guard reader.count >= 6 else { throw Failure.tooShort(id: id) }
        let format = Int(try reader.u16(0))
        guard format == 1 else { throw Failure.unsupportedFormat(id: id, format: format) }
        let synthCount = Int(try reader.u16(2))
        var offset = 4 + synthCount * 6  // each synth entry: 2-byte id + 4-byte initOption
        guard offset + 2 <= reader.count else { throw Failure.truncatedCommands(id: id) }
        let commandCount = Int(try reader.u16(offset))
        offset += 2
        guard offset + commandCount * 8 <= reader.count else { throw Failure.truncatedCommands(id: id) }
        var headerOffset: Int?
        for _ in 0..<commandCount {
            guard offset + 8 <= reader.count else { throw Failure.truncatedCommands(id: id) }
            let command = try reader.u16(offset)
            let param2 = Int(try reader.u32(offset + 4))
            offset += 8
            // CD 1.2 uses soundCmd (0x50) as well as bufferCmd (0x51).
            if command & 0x7FFF == 0x0050 || command & 0x7FFF == 0x0051 {
                guard command & 0x8000 != 0 else { throw Failure.pointerCommand(id: id) }
                headerOffset = param2
                break
            }
        }
        guard let header = headerOffset else { throw Failure.noBufferCommand(id: id) }
        guard header + 22 <= reader.count else { throw Failure.truncatedHeader(id: id, offset: header, length: reader.count) }
        let length = Int(try reader.u32(header + 4))
        let fixedRate = try reader.u32(header + 8)
        let encode = Int(try reader.u8(header + 20))
        guard encode == 0 else { throw Failure.unsupportedEncoding(id: id, encode: encode) }
        // Fixed 16.16 to Hz, rounded half-to-even like Python's round().
        let sampleRate = Int((Double(fixedRate) / 65536.0).rounded(.toNearestOrEven))
        let samplesStart = header + 22
        var samplesEnd = samplesStart + length
        let truncated = samplesEnd > reader.count
        if truncated { samplesEnd = reader.count }
        return Sound(sampleRate: sampleRate, bitsPerSample: 8,
                     pcm: try reader.data(samplesStart, samplesEnd - samplesStart), truncated: truncated)
    }

    /// 44-byte RIFF/WAVE PCM header plus samples, as Python's wave module writes it.
    static func wavData(sampleRate: Int, bitsPerSample: Int, channels: Int, pcm: Data) -> Data {
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channels * bytesPerSample
        var wav = Data(capacity: 44 + pcm.count)
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendU32LE(UInt32(36 + pcm.count))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.appendU32LE(16)
        wav.appendU16LE(1)  // PCM
        wav.appendU16LE(UInt16(channels))
        wav.appendU32LE(UInt32(sampleRate))
        wav.appendU32LE(UInt32(sampleRate * blockAlign))
        wav.appendU16LE(UInt16(blockAlign))
        wav.appendU16LE(UInt16(bitsPerSample))
        wav.append(contentsOf: Array("data".utf8))
        wav.appendU32LE(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    /// Writes sounds/snd_<id>.wav for every 'snd ' resource; returns the ids written.
    @discardableResult
    static func extractSounds(trailFork: MacResourceFork, into output: ExtractionOutput) throws -> [Int] {
        var written: [Int] = []
        for resource in trailFork.resources(ofType: "snd ") {
            let sound = try parseFormat1(resource.data, resourceID: resource.id)
            let wav = wavData(sampleRate: sound.sampleRate, bitsPerSample: sound.bitsPerSample, channels: 1, pcm: sound.pcm)
            try output.write(wav, to: "sounds/snd_\(resource.id).wav")
            written.append(resource.id)
        }
        return written
    }
}
