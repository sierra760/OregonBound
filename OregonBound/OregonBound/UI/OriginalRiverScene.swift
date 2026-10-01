import ImageIO
import SpriteKit
import SwiftUI

/// The original 262×155 crossing viewport. Rules and losses are resolved upstream.
struct OriginalRiverArtwork: View {
    let method: OriginalRiverAnimation.Method
    let outcome: OriginalRiverAnimation.Outcome
    var snow = false
    var failureKind: Int?
    var audio: GameAudio = .shared
    var onComplete: () -> Void
    @State private var scene = OriginalRiverScene()
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked

    var body: some View {
        SpriteView(scene: scene, isPaused: !visible || scenePhase != .active || modalBlocked, preferredFramesPerSecond: 60)
            .frame(width: 262, height: 155)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityLabel("Crossing the river")
            .onAppear {
                visible = true
                scene.setModalDispatchBlocked(modalBlocked)
                scene.start(method: method, outcome: outcome, snow: snow, failureKind: failureKind, audio: audio, onComplete: onComplete)
                scene.setActive(scenePhase == .active)
            }
            .onChange(of: method) { value in scene.start(method: value, outcome: outcome, snow: snow, failureKind: failureKind, audio: audio, onComplete: onComplete) }
            .onChange(of: outcome) { value in scene.start(method: method, outcome: value, snow: snow, failureKind: failureKind, audio: audio, onComplete: onComplete) }
            .onChange(of: snow) { value in scene.start(method: method, outcome: outcome, snow: value, failureKind: failureKind, audio: audio, onComplete: onComplete) }
            .onChange(of: scenePhase) { phase in scene.setActive(visible && phase == .active) }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear { visible = false; scene.setActive(false); scene.close() }
    }
}

final class OriginalRiverScene: SKScene {
    private var audio: GameAudio
    private var edition = GameEdition.macintosh11
    private var failureKind = 0
    private var audioCounter = 0
    private var ownsAudio = false
    private var animation: OriginalRiverAnimation?
    private var method: OriginalRiverAnimation.Method?
    private var outcome: OriginalRiverAnimation.Outcome?
    private var snow = false
    private var completion: (() -> Void)?
    private var completed = false
    private var active = false
    private var modalDispatchBlocked = false
    private var nextTick: UInt64?
    private var colorSpaceID: String?
    private var colorSpaceObservers: [NSObjectProtocol] = []
    private var textures: [Int: SKTexture] = [:]
    private var maskedTextures: [Int: SKTexture] = [:]
    private var sprites: [Int: SKSpriteNode] = [:]
    private let clip = SKCropNode()

    override convenience init() { self.init(audio: .shared) }
    init(audio: GameAudio) {
        self.audio = audio
        super.init(size: CGSize(width: 262, height: 155))
        scaleMode = .resizeFill
        backgroundColor = .black
        isUserInteractionEnabled = false
        let mask = SKSpriteNode(color: .white, size: size)
        mask.position = CGPoint(x: 131, y: 77.5)
        clip.maskNode = mask
        addChild(clip)
    }
    required init?(coder: NSCoder) { fatalError("OriginalRiverScene is created programmatically") }
    deinit { colorSpaceObservers.forEach(NotificationCenter.default.removeObserver) }

    func start(method: OriginalRiverAnimation.Method, outcome: OriginalRiverAnimation.Outcome, snow: Bool = false,
               failureKind: Int? = nil, audio: GameAudio? = nil, onComplete: @escaping () -> Void) {
        completion = onComplete
        let kind = failureKind ?? (outcome == .success ? 0 : 2)
        guard self.failureKind != kind || completed || self.method != method || self.outcome != outcome || self.snow != snow || animation == nil else { return }
        self.method = method; self.outcome = outcome; self.snow = snow
        let resource = OriginalResources.resource(monochrome: 5310, color: 15310)
        let sizes = OriginalResources.frames(resource).sorted { $0.frame_index < $1.frame_index }.map { ($0.width, $0.height) }
        let frames = OriginalRiverAnimation.displayFrames(sizes: sizes, edition: GameData.edition, snow: snow,
            color: OriginalResources.colorMode != .monochrome)
        close()
        if let audio { self.audio = audio }
        start(animation: OriginalRiverAnimation(method: method, outcome: outcome, frames: frames),
              failureKind: kind, edition: GameData.edition, onComplete: onComplete)
        render()
    }


    /// The supplied VM has already run its nondrawing initialization update.
    func start(animation: OriginalRiverAnimation, failureKind: Int, edition: GameEdition,
               onComplete: @escaping () -> Void) {
        close()
        self.animation = animation
        self.failureKind = failureKind
        self.edition = edition
        completion = onComplete
        audioCounter = 0
        ownsAudio = edition == .macintoshCD12
        completed = false
        nextTick = nil
    }

    /// Closing is separate from suspension. Finish releases audio synchronously
    /// before the next pane opens; later SwiftUI disappearance is harmless.
    func close() {
        if ownsAudio { ownsAudio = false; audio.clear() }
        completed = true
    }

    private func finish() {
        close()
        completion?()
    }

    /// Unlike native application suspension, a classic modal only skips idle calls.
    func setModalDispatchBlocked(_ value: Bool) {
        modalDispatchBlocked = value
        isPaused = !active || value
    }
    func setActive(_ value: Bool) {
        active = value
        isPaused = !value || modalDispatchBlocked
        nextTick = nil
    }

    override func didMove(to view: SKView) {
        colorSpaceObservers.forEach(NotificationCenter.default.removeObserver)
        colorSpaceObservers = TextureLoader.observeRenderingColorSpace(in: view) { [weak self] in self?.render() }
        render()
        isPaused = !active || modalDispatchBlocked
    }
    override func willMove(from view: SKView) {
        colorSpaceObservers.forEach(NotificationCenter.default.removeObserver)
        colorSpaceObservers.removeAll()
        setActive(false)
    }

    override func update(_ currentTime: TimeInterval) {
        guard active, !modalDispatchBlocked, !completed, animation != nil else { return }
        #if os(macOS)
        guard let window = view?.window, window.isVisible, window.occlusionState.contains(.visible) else {
            nextTick = nil
            return
        }
        #endif
        advance(to: UInt64(ProcessInfo.processInfo.systemUptime * 60))
        render()
    }

    /// Called only after the native visibility gate; also supports deterministic
    /// scene tests without presenting a window or depending on wall-clock time.
    func advance(to tick: UInt64) {
        guard active, !modalDispatchBlocked, !completed, animation != nil else { return }
        // CODE19 tests object-list emptiness before the timer deadline. Its final
        // VM update still executes the audio block; the next idle closes it.
        if edition == .macintoshCD12, animation?.isComplete == true { finish(); return }
        guard tick >= (nextTick ?? tick) else { return }
        animation?.step()
        if edition == .macintoshCD12 {
            for command in CDRiverAudio.commands(counter: audioCounter, failureKind: failureKind, busy: audio.isPlaying) {
                switch command {
                case .stop: audio.clear()
                case .start(let id): audio.request(id)
                }
            }
            audioCounter += 1
        } else if animation?.isComplete == true { finish(); return }
        nextTick = tick + UInt64(OriginalRiverAnimation.tickInterval)
    }

    private func render() {
        guard let animation, !animation.isComplete else { return }
        let identifier = TextureLoader.renderingColorSpaceID(for: view)
        if identifier != colorSpaceID {
            colorSpaceID = identifier
            textures.removeAll(); maskedTextures.removeAll()
            for entry in OriginalResources.frames(OriginalResources.resource(monochrome: 5310, color: 15310)) {
                textures[entry.frame_index] = TextureLoader.texture(for: entry, renderingIn: view)
                if [7,9,12].contains(entry.frame_index),
                   let url = GameData.resourceURL(entry.image_path),
                   let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                   let masked = Self.maskedImage(image) {
                    maskedTextures[entry.frame_index] = TextureLoader.texture(cgImage: masked, renderingIn: view)
                }
            }
        }
        let commands = animation.drawCommands
        let visible = Set(commands.map(\.object))
        for (id, sprite) in sprites { sprite.isHidden = !visible.contains(id) }
        for (index, command) in commands.enumerated() {
            let sprite: SKSpriteNode
            if let existing = sprites[command.object] { sprite = existing }
            else {
                sprite = SKSpriteNode()
                sprite.anchorPoint = CGPoint(x: 0, y: 1)
                sprites[command.object] = sprite
                clip.addChild(sprite)
            }
            sprite.isHidden = false
            sprite.texture = command.masked ? maskedTextures[command.frame] : textures[command.frame]
            sprite.blendMode = command.masked ? .alpha : .replace
            sprite.position = CGPoint(x: command.x-64, y: 155-(command.y-9))
            sprite.size = CGSize(width: command.width, height: command.height)
            sprite.zPosition = CGFloat(index)
        }
    }

    static func maskedImage(_ image: CGImage) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let rgba = TextureLoader.convertedImage(image, to: space),
              let data = rgba.dataProvider?.data else { return nil }
        var bytes = Array(data as Data)
        let white = stride(from: 0, to: bytes.count, by: 4).map {
            bytes[$0] == 255 && bytes[$0+1] == 255 && bytes[$0+2] == 255
        }
        let exterior = OriginalRiverMask.transparentPixels(width: image.width, height: image.height, white: white)
        for index in exterior.indices where exterior[index] {
            bytes.replaceSubrange(index*4..<index*4+4, with: [0,0,0,0])
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width*4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
