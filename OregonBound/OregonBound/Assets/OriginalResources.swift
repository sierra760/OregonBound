import SwiftUI
import AVFoundation

enum OriginalResources {
    static let manifest = BundleAssets.loadManifest()
    private struct Strings: Decodable { let strings: [String] }
    private struct GuideGroup: Decodable { struct Entry: Decodable { let text: String }; let entries: [Entry] }
    struct GuideEntry: Identifiable { let id: Int; let title: String; let text: String }

    static func strings(_ id: Int) -> [String] {
        guard let url = GameData.url(forResource: "str_\(id)", withExtension: "json", subdirectory: "strings"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Strings.self, from: data) else { return [] }
        return value.strings
    }

    static let guide: [GuideEntry] = {
        let titles = strings(3150)
        var texts: [String] = []
        for id in 3151...3171 {
            if let url = GameData.url(forResource: "wst_\(id)", withExtension: "json", subdirectory: "guidebook"),
               let data = try? Data(contentsOf: url), let group = try? JSONDecoder().decode(GuideGroup.self, from: data) { texts += group.entries.map(\.text) }
        }
        return zip(titles, texts).enumerated().map { index, entry in GuideEntry(id: index, title: entry.0, text: entry.1) }
    }()

    static func image(_ resource: Int, frame: Int = 0) -> Image? {
        guard let entry = manifest?.images(forResourceId: resource).first(where: { $0.frame_index == frame }),
              let path = GameData.resourceURL(entry.image_path) else { return nil }
        #if os(macOS)
        guard let image = NSImage(contentsOf: path) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: path.path) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

struct PixelArtwork: View {
    let resource: Int
    var frame = 0
    var body: some View {
        if let image = OriginalResources.image(resource, frame: frame) {
            image.resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Text("Artwork unavailable (\(resource))").font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

final class GameAudio {
    static let shared = GameAudio()
    var enabled: Bool {
        get { queue.enabled }
        set { apply(queue.setEnabled(newValue)) }
    }
    private var queue = OriginalAudioQueue()
    private let playback: OriginalAudioPlayback
    private let scheduleIdle: (@escaping () -> Void) -> Void
    private var idleScheduled = false
    private var generation: UInt64 = 0
    private var waitToken: UInt64 = 0
    private var waiters: [UInt64: () -> Void] = [:]

    init(playback: OriginalAudioPlayback = OriginalPCMPlayback(),
         scheduleIdle: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.playback = playback
        self.scheduleIdle = scheduleIdle
    }
    func play(_ id: Int) { request(id) }
    func request(_ id: Int) { apply(queue.request(id)) }
    func enqueue(_ id: Int) { queue.enqueue(id); schedulePump() }
    func clear() { apply(queue.clear()) }
    /// CODE1:33ba waits for current playback, with a180-tick maximum.
    func waitUntilIdle(_ completion: @escaping () -> Void) {
        guard queue.current != nil else { completion(); return }
        waitToken &+= 1
        let token = waitToken
        waiters[token] = completion
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { [weak self] in
            guard let self, self.waiters[token] != nil else { return }
            self.clear()
        }
        schedulePump()
    }

    private func notifyIdle() {
        guard queue.current == nil else { return }
        let callbacks = Array(waiters.values)
        waiters.removeAll()
        callbacks.forEach { $0() }
    }

    private func schedulePump() {
        guard !idleScheduled else { return }
        idleScheduled = true
        scheduleIdle { [weak self] in
            guard let self else { return }
            self.idleScheduled = false
            self.apply(self.queue.pump())
            // Muted enqueues consume one entry per idle, as CODE1:31e4 does.
            if self.queue.current == nil && !self.queue.pending.isEmpty { self.schedulePump() }
        }
    }
    private func apply(_ commands: [OriginalAudioQueue.Command]) {
        for command in commands {
            switch command {
            case .stop:
                generation &+= 1
                playback.stop()
            case .start(let id):
                generation &+= 1
                let token = generation
                let started = playback.start(id) { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.queue.completed()
                    self.schedulePump()
                }
                if !started { apply(queue.clear()) }
            }
        }
        notifyIdle()
    }
}
