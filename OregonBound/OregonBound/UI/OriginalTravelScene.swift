import ImageIO
import SpriteKit
import SwiftUI

/// The original moving overland viewport, separate from the 262×155 landmark art.
struct OriginalTravelArtwork: View {
    let trip: Journey
    let moving: Bool
    @State private var scene = OriginalTravelScene()
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked

    var body: some View {
        SpriteView(scene: scene, isPaused: !visible || scenePhase != .active || modalBlocked,
                   preferredFramesPerSecond: 60)
            .frame(width: 262, height: 77)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityLabel("Traveling along the Oregon Trail")
            .onAppear {
                visible = true
                scene.setModalDispatchBlocked(modalBlocked)
                scene.show(trip: trip, moving: moving)
                scene.setActive(scenePhase == .active)
            }
            .onChange(of: trip) { value in scene.show(trip: value, moving: moving) }
            .onChange(of: moving) { value in scene.show(trip: trip, moving: value) }
            .onChange(of: scenePhase) { phase in scene.setActive(visible && phase == .active) }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear {
                visible = false
                scene.setActive(false)
            }
    }
}

/// Replaces palette entries, preserving pixel indices even where two entries
/// have identical RGB. Original Imag PNGs retain their indexed color spaces.
enum OriginalTravelPalette {
    static func replacing(in image: CGImage, with palette: OriginalTravelAnimation.Palette) -> CGImage? {
        guard let original = image.colorSpace, original.model == .indexed,
              let base = original.baseColorSpace, base.numberOfComponents == 3,
              var colors = original.colorTable, colors.count >= 234 * 3,
              let provider = image.dataProvider else { return nil }
        let ground = Array(colors[palette.groundSource * 3..<palette.groundSource * 3 + 3])
        let sky = Array(colors[palette.skySource * 3..<palette.skySource * 3 + 3])
        colors.replaceSubrange(229 * 3..<230 * 3, with: ground)
        colors.replaceSubrange(233 * 3..<234 * 3, with: sky)
        guard let space = CGColorSpace(indexedBaseSpace: base, last: colors.count / 3 - 1, colorTable: &colors) else { return nil }
        return CGImage(width: image.width, height: image.height,
                       bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
                       bytesPerRow: image.bytesPerRow, space: space, bitmapInfo: image.bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: false, intent: image.renderingIntent)
    }
}

final class OriginalTravelScene: SKScene {
    private let resource = OriginalResources.resource(monochrome: 5100, color: 15100)
    private var animation: OriginalTravelAnimation?
    private var active = false
    private var modalDispatchBlocked = false
    private var moving = false
    private var nextTick: UInt64?
    private var colorSpaceID: String?
    private var colorSpaceObservers: [NSObjectProtocol] = []
    private let clip = SKCropNode()
    private var sprites: [SKSpriteNode] = []
    private var entries: [Int: ManifestImage] = [:]
    private var paletteTextures: [String: SKTexture] = [:]
    private var indexedImages: [Int: CGImage] = [:]

    override init() {
        super.init(size: CGSize(width: 262, height: 77))
        scaleMode = .resizeFill
        backgroundColor = .black
        isUserInteractionEnabled = false
        let mask = SKSpriteNode(color: .white, size: size)
        mask.position = CGPoint(x: 131, y: 38.5)
        clip.maskNode = mask
        addChild(clip)
    }

    required init?(coder: NSCoder) { fatalError("OriginalTravelScene is created programmatically") }

    func show(trip: Journey, moving: Bool) {
        let id = trip.phase == .travel ? trip.destinationID : trip.locationID
        let destination = TrailCatalog.stops.firstIndex(where: { $0.id == id }).map { $0 - 1 } ?? -1
        let input = OriginalTravelAnimation.Input(
            pace: Int(trip.pace.originalIndex), destinationIndex: destination,
            remainingMiles: trip.phase == .travel ? trip.milesToNext : 0,
            month: trip.month, weather: trip.originalWeatherCategory,
            snow: Int(trip.original?.weather.snow ?? 0),
            lastMovement: Int(trip.original?.lastMovement ?? 0),
            dayDelay: Int(trip.timing.timerThreshold),
            crossingPending: trip.originalRiverOutcome != nil)
        if animation == nil {
            let frames = OriginalResources.frames(resource).sorted { $0.frame_index < $1.frame_index }
            guard frames.map(\.frame_index) == Array(OriginalTravelAnimation.frameSizes.indices) else { return }
            animation = OriginalTravelAnimation(input: input,
                upperStripWidth: frames[1].width, lowerStripWidth: frames[2].width,
                frameSizes: frames.map { ($0.width, $0.height) })
        }
        else { animation?.apply(input) }
        let shouldMove = moving && trip.phase == .travel
        if self.moving != shouldMove { nextTick = nil }
        self.moving = shouldMove
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

        for entry in OriginalResources.frames(resource) {
            entries[entry.frame_index] = entry
        }
        render()
        isPaused = !active || modalDispatchBlocked
    }

    deinit { colorSpaceObservers.forEach(NotificationCenter.default.removeObserver) }

    override func willMove(from view: SKView) {
        colorSpaceObservers.forEach(NotificationCenter.default.removeObserver)
        colorSpaceObservers.removeAll()
        setActive(false)
    }

    override func update(_ currentTime: TimeInterval) {
        guard active, !modalDispatchBlocked, moving else { return }
        #if os(macOS)
        guard let window = view?.window, window.isVisible, window.occlusionState.contains(.visible) else {
            nextTick = nil
            return
        }
        #endif
        let tick = UInt64(ProcessInfo.processInfo.systemUptime * 60)
        guard tick >= (nextTick ?? tick) else { return }
        animation?.step(readTick: { Int(ProcessInfo.processInfo.systemUptime * 60) })
        render()
        nextTick = UInt64(ProcessInfo.processInfo.systemUptime * 60) + UInt64(OriginalTravelAnimation.tickInterval)
    }

    private func render() {
        guard let animation else { return }
        let identifier = TextureLoader.renderingColorSpaceID(for: view)
        if identifier != colorSpaceID {
            colorSpaceID = identifier
            paletteTextures.removeAll()
        }
        let commands = animation.drawCommands
        if sprites.count != commands.count {
            clip.removeAllChildren()
            sprites = commands.indices.map { index in
                let sprite = SKSpriteNode()
                sprite.anchorPoint = CGPoint(x: 0, y: 1)
                sprite.zPosition = CGFloat(index)
                sprite.blendMode = .replace
                clip.addChild(sprite)
                return sprite
            }
        }
        for (sprite, command) in zip(sprites, commands) {
            sprite.texture = texture(frame: command.frame, palette: animation.palette)
            let rect = command.destination
            sprite.position = CGPoint(x: CGFloat(rect.x - 64), y: CGFloat(77 - (rect.y - 9)))
            sprite.size = CGSize(width: CGFloat(rect.width), height: CGFloat(rect.height))
        }
    }

    private func texture(frame: Int, palette: OriginalTravelAnimation.Palette) -> SKTexture? {
        guard let entry = entries[frame] else { return nil }
        if OriginalResources.colorMode != .color256 || (palette.groundSource == 226 && palette.skySource == 230) {
            return TextureLoader.texture(for: entry, renderingIn: view)
        }
        let key = "\(frame):\(palette.groundSource):\(palette.skySource)"
        if let texture = paletteTextures[key] { return texture }
        if indexedImages[frame] == nil,
           let url = GameData.resourceURL(entry.image_path),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            indexedImages[frame] = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let source = indexedImages[frame],
              let image = OriginalTravelPalette.replacing(in: source, with: palette) else {
            return TextureLoader.texture(for: entry, renderingIn: view)
        }
        let texture = TextureLoader.texture(cgImage: image, renderingIn: view)
        texture.filteringMode = .nearest
        paletteTextures[key] = texture
        return texture
    }
}
