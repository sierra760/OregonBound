import SwiftUI
import AVFoundation

enum OriginalResources {
    private static let manifestCache = SessionResourceCache<String, GraphicsManifest>()
    private static let guideCache = SessionResourceCache<String, [GuideEntry]>()
    static var manifest: GraphicsManifest? {
        manifestCache.value(for: "graphics", session: GameData.sessionID) { BundleAssets.loadManifest() }
    }
    static var imageType: String { GameData.preparedSession?.imageType ?? "Imag" }
    static func frames(_ resource: Int) -> [ManifestImage] {
        manifest?.images(forResourceId: resource).filter { $0.resource.type == imageType } ?? []
    }
    private struct Strings: Decodable { let strings: [String] }
    private struct GuideGroup: Decodable { struct Entry: Decodable { let text: String }; let entries: [Entry] }
    struct GuideEntry: Identifiable { let id: Int; let title: String; let text: String }

    static func strings(_ id: Int) -> [String] {
        guard let url = GameData.url(forResource: "str_\(id)", withExtension: "json", subdirectory: "strings"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Strings.self, from: data) else { return [] }
        return value.strings
    }

    static var guide: [GuideEntry] {
        guideCache.value(for: "guide", session: GameData.sessionID, load: loadGuide) ?? []
    }
    private static func loadGuide() -> [GuideEntry] {
        loadGuide(edition: GameData.edition, titles: strings(3150)) { id in
            guard let url = GameData.url(forResource: "wst_\(id)", withExtension: "json", subdirectory: "guidebook"),
                  let data = try? Data(contentsOf: url),
                  let group = try? JSONDecoder().decode(GuideGroup.self, from: data) else { return nil }
            return group.entries.map(\.text)
        }
    }

    /// Preserve page identity even when a group/slot is unavailable. Concatenation
    /// would incorrectly pair every subsequent title with an earlier page's text.
    static func loadGuide(edition: GameEdition, titles: [String], group: (Int) -> [String]?) -> [GuideEntry] {
        var result: [GuideEntry] = []
        var entries: [String] = []
        for index in 0..<min(titles.count, OriginalGuide.pageCount(for: edition)) {
            if index % 3 == 0 { entries = group(3151 + index / 3) ?? [] }
            guard entries.indices.contains(index % 3) else { continue }
            result.append(GuideEntry(id: index, title: titles[index], text: entries[index % 3]))
        }
        return result
    }

    static func image(_ resource: Int, type: String? = nil, frame: Int = 0) -> Image? {
        guard let entry = manifest?.image(resource: resource, type: type, frame: frame),
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
    var type: String? = nil
    var body: some View {
        if let image = OriginalResources.image(resource, type: type, frame: frame) {
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
    private var sessionGeneration: UInt64 = 0
    private var generation: UInt64 = 0
    private var waitToken: UInt64 = 0
    private var waiters: [UInt64: () -> Void] = [:]

    init(playback: OriginalAudioPlayback = OriginalPCMPlayback(),
         scheduleIdle: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.playback = playback
        self.scheduleIdle = scheduleIdle
    }
    var isPlaying: Bool { queue.isPlaying }
    func perform(_ action: OriginalGuide.AudioAction) {
        switch action {
        case .none: break
        case .stop: clear()
        case .request(let id): request(id)
        }
    }
    func play(_ id: Int) { request(id) }
    func request(_ id: Int) { apply(queue.request(id)) }
    func enqueue(_ id: Int) { queue.enqueue(id); schedulePump() }
    func clear() { apply(queue.clear()) }
    /// End the old session without resuming its queued cleanup callbacks.
    func resetForSession() {
        sessionGeneration &+= 1
        generation &+= 1
        waiters.removeAll()
        queue = OriginalAudioQueue()
        idleScheduled = false
        playback.stop()
    }
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
        let session = sessionGeneration
        scheduleIdle { [weak self] in
            guard let self, self.sessionGeneration == session else { return }
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
