import ImageIO
import SpriteKit
import SwiftUI

/// The original user item is (9,9)-(503,271) in the 512×322 window.
struct OriginalHuntArtwork: View {
    let scene: OriginalHuntScene
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked

    var body: some View {
        SpriteView(scene: scene, isPaused: !visible || scenePhase != .active || modalBlocked, preferredFramesPerSecond: 60)
            .frame(width: 512, height: 322)
            .offset(x: -OriginalWindowLayout.contentOrigin.x, y: -OriginalWindowLayout.contentOrigin.y)
            .frame(width: 494, height: 262, alignment: .topLeading)
            .clipped()
            .overlay {
                #if os(macOS)
                OriginalHuntCursorArea().allowsHitTesting(false)
                #endif
            }
            .accessibilityLabel("Hunting ground. Aim and fire; Move changes the hunting ground.")
            .onAppear { visible = true; scene.setModalDispatchBlocked(modalBlocked); scene.setActive(scenePhase == .active) }
            .onChange(of: scenePhase) { phase in scene.setActive(visible && phase == .active) }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear { visible = false; scene.setActive(false) }
    }
}

@MainActor final class OriginalHuntScene: SKScene, ObservableObject {
    private(set) var session: OriginalHuntSession
    private let random: OriginalRandomStream
    private let completion: (OriginalHuntSession.Result) -> Void
    private var active = false
    private var modalDispatchBlocked = false
    private var completionSent = false
    private var pendingCompletion: OriginalHuntSession.Result?
    private var colorSpaceID: String?
    private var colorSpaceObservers: [NSObjectProtocol] = []
    private var textures: [String: SKTexture] = [:]
    private var sprites: [Int: SKSpriteNode] = [:]
    private let fills = SKNode()
    private let clip = SKCropNode()
    private static var tick: Int { Int(ProcessInfo.processInfo.systemUptime * 60) }

    init(input: OriginalHuntSession.Input, random: OriginalRandomStream,
         onFinish: @escaping (OriginalHuntSession.Result) -> Void) {
        let tick = Self.tick
        session = OriginalHuntSession(input: input,startTick: tick,deferInitialScenery: true) { random.bounded($0) }
        session.setPaused(true,at: tick)
        self.random = random
        completion = onFinish
        super.init(size: CGSize(width: 512, height: 322))
        scaleMode = .fill
        backgroundColor = .black
        isUserInteractionEnabled = true
        let viewport = OriginalHuntSession.viewport
        let mask = SKSpriteNode(color: .white, size: CGSize(width: viewport.width, height: viewport.height))
        mask.position = CGPoint(x: viewport.x + viewport.width / 2, y: 322 - viewport.y - viewport.height / 2)
        clip.maskNode = mask
        fills.zPosition = -1
        clip.addChild(fills)
        addChild(clip)
    }
    convenience init(input: OriginalHuntSession.Input,seed: UInt32,
                     onFinish: @escaping (OriginalHuntSession.Result,UInt32)->Void) {
        let stream = OriginalRandomStream(seed: seed)
        self.init(input: input,random: stream) { result in onFinish(result,stream.seed) }
    }
    required init?(coder: NSCoder) { fatalError("OriginalHuntScene is created programmatically") }
    deinit { colorSpaceObservers.forEach(NotificationCenter.default.removeObserver) }

    func prepareSound() { GameAudio.shared.request(9007) }
    func move() { guard active, !modalDispatchBlocked else { return }; session.move() }
    func stop() { guard active, !modalDispatchBlocked else { return }; session.stop() }
    /// Unlike native application suspension, a classic modal only skips idle calls.
    func setModalDispatchBlocked(_ value: Bool) {
        modalDispatchBlocked = value
        isPaused = !active || value
    }
    func setActive(_ value: Bool) {
        if value && !modalDispatchBlocked { let stream = random; session.beginScene { stream.bounded($0) } }
        active = value
        session.setPaused(!value, at: Self.tick)
        isPaused = !value || modalDispatchBlocked
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
        guard active, !modalDispatchBlocked else { return }
        deliverPendingCompletion()
        guard !completionSent else { return }
        let tick = Self.tick
        #if os(macOS)
        guard let window = view?.window, window.isVisible, window.occlusionState.contains(.visible) else {
            session.setPaused(true, at: tick)
            return
        }
        #endif
        session.setPaused(false, at: tick)
        let stream = random
        session.beginScene { stream.bounded($0) }
        session.advance(to: tick) { stream.bounded($0) }
        render()
        deliverEvents()
    }
    private func fire(at point: CGPoint) {
        let x = Int(point.x), y = Int(322-point.y)
        guard active, !modalDispatchBlocked, OriginalHuntSession.viewport.contains(x: x, y: y) else { return }
        _ = session.shoot(x: x, y: y)
        deliverEvents()
    }
    #if os(macOS)
    override func mouseDown(with event: NSEvent) { fire(at: event.location(in: self)) }
    #else
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { fire(at: touch.location(in: self)) }
    }
    #endif
    private func deliverEvents() {
        for event in session.takeEvents() {
            switch event {
            case .fired: GameAudio.shared.clear(); GameAudio.shared.enqueue(9002)
            case .dryFire: GameAudio.shared.clear(); GameAudio.shared.enqueue(9004)
            case .hit: GameAudio.shared.clear(); GameAudio.shared.enqueue(9003)
            case .finished(let result):
                guard !completionSent else { continue }
                completionSent = true
                // Do not publish SwiftUI navigation changes from SpriteKit's render callback.
                GameAudio.shared.waitUntilIdle { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        self?.pendingCompletion = result
                        self?.deliverPendingCompletion()
                    }
                }
            case .blocked, .missed: break
            }
        }
    }
    private func deliverPendingCompletion() {
        guard active, !modalDispatchBlocked, let result = pendingCompletion else { return }
        pendingCompletion = nil
        completion(result)
    }
    private func render() {
        let identifier = TextureLoader.renderingColorSpaceID(for: view)
        if colorSpaceID != identifier {
            colorSpaceID = identifier
            textures.removeAll()
            fills.removeAllChildren()
            for command in session.fillCommands {
                guard let image = OriginalHuntImage.solid(rgb16: command.rgb16) else { continue }
                let node = SKSpriteNode(texture: TextureLoader.texture(cgImage: image, renderingIn: view))
                node.anchorPoint = CGPoint(x: 0, y: 1)
                node.position = CGPoint(x: command.rect.x, y: 322-command.rect.y)
                node.size = CGSize(width: command.rect.width, height: command.rect.height)
                node.blendMode = .replace
                fills.addChild(node)
            }
        }
        let commands = session.drawCommands
        let visible = Set(commands.map(\.id))
        for id in Array(sprites.keys) where !visible.contains(id) {
            sprites.removeValue(forKey: id)?.removeFromParent()
        }
        for (depth, command) in commands.enumerated() {
            let node = sprites[command.id] ?? SKSpriteNode()
            if node.parent == nil { clip.addChild(node); sprites[command.id] = node }
            node.texture = texture(for: command)
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.position = CGPoint(x: command.rect.x + (command.mirrored ? command.rect.width : 0),
                                    y: 322-command.rect.y)
            node.size = CGSize(width: command.rect.width, height: command.rect.height)
            node.xScale = command.mirrored ? -1 : 1
            node.zPosition = CGFloat(depth)
            node.blendMode = command.transfer == .copy ? .replace : .alpha
        }
    }
    private func texture(for command: OriginalHuntSession.DrawCommand) -> SKTexture? {
        let key = "\(command.resource):\(command.frame):\(command.transfer.rawValue)"
        if let cached = textures[key] { return cached }
        guard let entry = OriginalResources.manifest?.images(forResourceId: command.resource)
            .first(where: { $0.resource.type == "Imag" && $0.frame_index == command.frame }),
              let url = GameData.resourceURL(entry.image_path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let swapped = OriginalHuntImage.substitutingPalette(in: image, palette: session.palette) else { return nil }
        // Frame19160/3 is black with four white corner pixels: its original srcOr
        // is identical to drawing opaque black with those white corners transparent.
        let prepared = command.transfer == .copy ? swapped : OriginalRiverScene.maskedImage(swapped)
        guard let prepared else { return nil }
        let result = TextureLoader.texture(cgImage: prepared, renderingIn: view)
        textures[key] = result
        return result
    }
}

/// Source palette operations precede CalcCMask and destination-profile conversion.
enum OriginalHuntImage {
    static func substitutingPalette(in source: CGImage, palette: OriginalHuntSession.Palette) -> CGImage? {
        guard let space = source.colorSpace, space.model == .indexed,
              var colors = space.colorTable, colors.count >= 256*3 else { return nil }
        for (destination, origin) in [(1,palette.skyIndex),(2,palette.groundIndex)] {
            colors.replaceSubrange(destination*3..<destination*3+3, with: colors[origin*3..<origin*3+3])
        }
        guard let indexed = CGColorSpace(indexedBaseSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         last: colors.count/3-1, colorTable: &colors) else { return nil }
        return source.copy(colorSpace: indexed)
    }
    static func solid(rgb16: [Int]) -> CGImage? {
        let bytes = rgb16.map { UInt8(clamping: $0 >> 8) } + [255]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

#if os(macOS)
/// AppKit cursor rectangles restore the normal cursor when leaving the user item.
private struct OriginalHuntCursorArea: NSViewRepresentable {
    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            if let cursor = Self.cursor { addCursorRect(bounds,cursor: cursor) }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
        private static let cursor: NSCursor? = {
            guard let provider = CGDataProvider(data: Data(OriginalHuntCursor.rgba) as CFData),
                  let image = CGImage(width: 16,height: 16,bitsPerComponent: 8,bitsPerPixel: 32,
                    bytesPerRow: 64,space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { return nil }
            return NSCursor(image: NSImage(cgImage: image,size: NSSize(width: 16,height: 16)),
                            hotSpot: NSPoint(x: OriginalHuntCursor.hotspotX,y: OriginalHuntCursor.hotspotY))
        }()
    }
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) { view.window?.invalidateCursorRects(for: view) }
}
#endif
