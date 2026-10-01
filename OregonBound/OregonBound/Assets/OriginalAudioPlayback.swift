import AVFoundation

/// Native output boundary. Scheduling policy belongs to OriginalAudioQueue.
protocol OriginalAudioPlayback: AnyObject {
    func start(_ resource: Int, completion: @escaping () -> Void) -> Bool
    func stop()
}

final class OriginalPCMPlayback: OriginalAudioPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffers = SessionResourceCache<Int, AVAudioPCMBuffer>()

    init() { engine.attach(player) }
    func start(_ resource: Int, completion: @escaping () -> Void) -> Bool {
        guard let buffer = buffer(for: resource) else { return false }
        player.stop()
        engine.pause()
        engine.disconnectNodeOutput(player)
        // AVAudioEngine's mixer converts the original fractional rate to the device's rate.
        engine.connect(player,to: engine.mainMixerNode,format: buffer.format)
        engine.prepare()
        do { try engine.start() } catch { return false }
        player.scheduleBuffer(buffer,completionCallbackType: .dataPlayedBack) { _ in
            // The Sound Manager callback likewise only marks completion; queue pumping is separate.
            DispatchQueue.main.async(execute: completion)
        }
        player.play()
        return true
    }
    func stop() { player.stop() }

    private func buffer(for resource: Int) -> AVAudioPCMBuffer? {
        buffers.value(for: resource, session: GameData.sessionID) { makeBuffer(for: resource) }
    }

    private func makeBuffer(for resource: Int) -> AVAudioPCMBuffer? {
        let sample: OriginalSoundSample?
        if let session = GameData.preparedSession {
            sample = try? session.sounds.sample(resource)
        } else if let url = GameData.url(forResource: "snd_\(resource)", withExtension: "wav", subdirectory: "sounds"),
                  let wav = try? Data(contentsOf: url) {
            sample = OriginalSoundSample(resource: resource, wav: wav)
        } else { sample = nil }
        guard let sample,
              let format = AVAudioFormat(standardFormatWithSampleRate: sample.sampleRate,channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: AVAudioFrameCount(sample.samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for (index, value) in sample.samples.enumerated() { channel[index] = (Float(value)-128)/128 }
        return buffer
    }
}
