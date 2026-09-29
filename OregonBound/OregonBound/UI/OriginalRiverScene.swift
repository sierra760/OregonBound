import ImageIO
import SpriteKit
import SwiftUI

/// The original 262×155 crossing viewport. Rules and losses are resolved upstream.
struct OriginalRiverArtwork: View {
    let method: OriginalRiverAnimation.Method
    let outcome: OriginalRiverAnimation.Outcome
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
                scene.start(method: method, outcome: outcome, onComplete: onComplete)
                scene.setActive(scenePhase == .active)
            }
            .onChange(of: method) { value in scene.start(method: value, outcome: outcome, onComplete: onComplete) }
            .onChange(of: outcome) { value in scene.start(method: method, outcome: value, onComplete: onComplete) }
            .onChange(of: scenePhase) { phase in scene.setActive(visible && phase == .active) }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear { visible = false; scene.setActive(false) }
    }
}

final class OriginalRiverScene: SKScene {
    private var animation: OriginalRiverAnimation?
    private var method: OriginalRiverAnimation.Method?
    private var outcome: OriginalRiverAnimation.Outcome?
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

    override init() {
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

    func start(method: OriginalRiverAnimation.Method, outcome: OriginalRiverAnimation.Outcome,
               onComplete: @escaping () -> Void) {
        completion = onComplete
        guard self.method != method || self.outcome != outcome || animation == nil else { return }
        self.method = method; self.outcome = outcome
        animation = OriginalRiverAnimation(method: method, outcome: outcome)
        completed = false
        nextTick = nil
        render()
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
        let tick = UInt64(ProcessInfo.processInfo.systemUptime * 60)
        guard tick >= (nextTick ?? tick) else { return }
        animation?.step()
        if animation?.isComplete == true {
            completed = true
            completion?()
            return
        }
        render()
        nextTick = UInt64(ProcessInfo.processInfo.systemUptime * 60) + UInt64(OriginalRiverAnimation.tickInterval)
    }

    private func render() {
        guard let animation, !animation.isComplete else { return }
        let identifier = TextureLoader.renderingColorSpaceID(for: view)
        if identifier != colorSpaceID {
            colorSpaceID = identifier
            textures.removeAll(); maskedTextures.removeAll()
            for entry in OriginalResources.manifest?.images(forResourceId: 15310) ?? [] where entry.resource.type == "Imag" {
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
