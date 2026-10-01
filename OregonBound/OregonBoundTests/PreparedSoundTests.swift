import Foundation
import Testing
@testable import OregonBound

struct PreparedSoundTests {
    private let rate: UInt32 = 729236945
    private let pcm = Data([0, 128, 255])
    private func resource(_ id: Int = 17000) -> MacResource {
        var bytes = Data()
        bytes.appendU16(1); bytes.appendU16(0); bytes.appendU16(1)
        bytes.appendU16(0x8050); bytes.appendU16(0); bytes.appendU32(14)
        bytes.appendU32(0); bytes.appendU32(UInt32(pcm.count)); bytes.appendU32(rate)
        bytes.appendU32(0); bytes.appendU32(0); bytes.append(contentsOf: [0, 60]); bytes.append(pcm)
        return .init(type: "snd ", id: id, name: nil, attributes: 0, data: bytes)
    }
    private func wave() -> Data {
        SoundExtractor.wavData(sampleRate: 11127, bitsPerSample: 8, channels: 1, pcm: pcm)
    }
    private func record() -> SoundExtractor.Record {
        .init(id: 17000, sampleCount: pcm.count, fixedSampleRate: rate, path: "sounds/snd_17000.wav")
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func preservesExactRateAndEmitsOptionalMetadata() throws {
        let parsed = try SoundExtractor.parseFormat1(resource().data, strict: true)
        #expect(parsed.fixedSampleRate == rate)
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let output = ExtractionOutput(root: root)
        let fork = MacResourceFork(resources: [resource()])
        try SoundExtractor.extractSounds(trailFork: fork, into: output)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("sounds/manifest.json").path))
        try SoundExtractor.extractSounds(trailFork: fork, into: output, strict: true, includeMetadata: true)
        let manifest = try JSONDecoder().decode(SoundExtractor.Manifest.self, from: Data(contentsOf: root.appendingPathComponent("sounds/manifest.json")))
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.sounds.count == 1)
        #expect(manifest.sounds[0].fixedSampleRate == rate)
        #expect(manifest.sounds[0].sampleCount == pcm.count)
        #expect(manifest.sounds[0].path == "sounds/snd_17000.wav")
    }
    @Test func arbitrarySoundUsesItsExactRateAndUnchangedSamples() throws {
        let sound = try #require(OriginalSoundSample(record: record(), wav: wave()))
        #expect(sound.samples == Array(pcm))
        #expect(sound.sampleRate == Double(rate) / 65536)
    }
    @Test(arguments: ["rate", "byte_rate", "count", "riff_extent", "format", "duplicate_data", "duplicate_format", "zero_rate"])
    func rejectsInconsistentWaveAndMetadata(kind: String) {
        var wav = wave()
        var metadata = record()
        switch kind {
        case "rate": wav[24] ^= 1
        case "byte_rate": wav[28] ^= 1
        case "count": metadata = .init(id: 17000, sampleCount: 4, fixedSampleRate: rate, path: record().path)
        case "riff_extent": wav[4] ^= 1
        case "format": wav[22] = 2
        case "zero_rate": metadata = .init(id: 17000, sampleCount: 3, fixedSampleRate: 0, path: record().path)
        default:
            wav.append(0) // align odd PCM chunk before another chunk
            wav.append(kind == "duplicate_data" ? wave().subdata(in: 36..<47) : wave().subdata(in: 12..<36))
            let length = UInt32(wav.count - 8)
            wav.replaceSubrange(4..<8, with: withUnsafeBytes(of: length.littleEndian) { Data($0) })
        }
        #expect(OriginalSoundSample(record: metadata, wav: wav) == nil)
    }
    @Test func libraryUsesSelectedSourceAndNeverFallsBack() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let entry = GameResourceCatalog.Entry(role: .guide1, type: "snd ", id: 17000, name: nil, attributes: 0, length: 39, sha256: "fixture", disposition: .resource)
        let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: [entry])
        let output = ExtractionOutput(root: root.appendingPathComponent("sources/guide1"))
        try SoundExtractor.extractSounds(trailFork: MacResourceFork(resources: [resource()]), into: output, strict: true, includeMetadata: true)
        let library = try PreparedSoundLibrary(root: root, lookup: lookup, soundSources: [.guide1])
        #expect(try library.sample(17000)?.samples == Array(pcm))
        #expect(try library.sample(17001) == nil)
        try FileManager.default.removeItem(at: output.url(record().path))
        try ExtractionOutput(root: root).write(wave(), to: record().path)
        #expect(throws: (any Error).self) { try library.sample(17000) }
    }
    @Test func unpreparedSystemSoundsDoNotPreventGameAudioLoading() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let game = GameResourceCatalog.Entry(role: .guide1, type: "snd ", id: 17000, name: nil, attributes: 0, length: 39, sha256: "fixture", disposition: .resource)
        let system = GameResourceCatalog.Entry(role: .system, type: "snd ", id: 1, name: nil, attributes: 0, length: 39, sha256: "fixture", disposition: .resource)
        let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: [game, system])
        try SoundExtractor.extractSounds(trailFork: MacResourceFork(resources: [resource()]),
            into: ExtractionOutput(root: root.appendingPathComponent("sources/guide1")), strict: true, includeMetadata: true)
        let library = try PreparedSoundLibrary(root: root, lookup: lookup, soundSources: [.guide1])
        #expect(try library.sample(17000)?.samples == Array(pcm))
        #expect(try library.sample(1) == nil)
    }

    @Test(arguments: ["duplicate", "missing", "path", "schema"])
    func libraryRejectsBrokenSourceManifest(kind: String) throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let entry = GameResourceCatalog.Entry(role: .guide1, type: "snd ", id: 17000, name: nil, attributes: 0, length: 39, sha256: "fixture", disposition: .resource)
        let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: [entry])
        let sounds: [SoundExtractor.Record]
        switch kind {
        case "duplicate": sounds = [record(), record()]
        case "missing": sounds = []
        case "path": sounds = [.init(id: 17000, sampleCount: 3, fixedSampleRate: rate, path: "../../other.wav")]
        default: sounds = [record()]
        }
        try ExtractionOutput(root: root.appendingPathComponent("sources/guide1")).writeJSON(
            SoundExtractor.Manifest(schemaVersion: kind == "schema" ? 99 : 1, sounds: sounds), to: "sounds/manifest.json")
        #expect(throws: (any Error).self) { try PreparedSoundLibrary(root: root, lookup: lookup, soundSources: [.guide1]) }
    }
}
