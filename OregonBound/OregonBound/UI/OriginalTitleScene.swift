import SpriteKit
import SwiftUI

/// Exact title composition in the full 512×322 Macintosh content coordinates.
/// The SwiftUI wrapper compensates for the surrounding dialog's (9,9) origin.
struct OriginalTitleArtwork: View {
    @StateObject private var holder = OriginalTitleSceneHolder()
    private var scene: OriginalTitleScene { holder.scene }
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked

    var body: some View {
        OriginalSpriteView(scene: scene, isPaused: !visible || scenePhase != .active || modalBlocked, preferredFramesPerSecond: 60)
            .frame(width: 512, height: 322)
            .offset(x: -OriginalWindowLayout.contentOrigin.x, y: -OriginalWindowLayout.contentOrigin.y)
            .frame(width: 494, height: 304, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                visible = true
                scene.setModalDispatchBlocked(modalBlocked)
                scene.setActive(scenePhase == .active)
            }
            .onChange(of: scenePhase) { phase in
                scene.setActive(visible && phase == .active)
            }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear {
                visible = false
                scene.setActive(false)
            }
    }
}

@MainActor private final class OriginalTitleSceneHolder: ObservableObject {
    let scene = OriginalTitleScene()
}

final class OriginalTitleScene: SKScene {
    private var animation: OriginalTitleAnimation
    private var textures: [Int: SKTexture] = [:]
    private var sprites: [SKSpriteNode] = []
    private var active = false
    private var modalDispatchBlocked = false
    private var nextTick: UInt64?
    private var colorSpaceID: String?
    private var colorSpaceObservers: [NSObjectProtocol] = []

    override init() {
        animation = OriginalTitleAnimation { OriginalRandomStream.shared.bounded($0) }
        super.init(size: CGSize(width: 512, height: 322))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 1, green: 246.0 / 255, blue: 137.0 / 255, alpha: 1)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("OriginalTitleScene is created programmatically") }

    /// Unlike native application suspension, a classic modal only skips idle calls.
    func setModalDispatchBlocked(_ value: Bool) {
        modalDispatchBlocked = value
        isPaused = !active || value
    }
    func setActive(_ value: Bool) {
        active = value
        isPaused = !value || modalDispatchBlocked
        // No catch-up after a hidden view or inactive application resumes.
        nextTick = nil
    }

    override func didMove(to view: SKView) {
        colorSpaceObservers.forEach(NotificationCenter.default.removeObserver)
        colorSpaceObservers = TextureLoader.observeRenderingColorSpace(in: view) { [weak self] in
            self?.refreshRenderingColorSpace()
        }
        refreshRenderingColorSpace()
        guard sprites.isEmpty else { return }
        for (index, command) in animation.drawCommands.enumerated() {
            let sprite = SKSpriteNode(texture: textures[command.frame])
            sprite.anchorPoint = CGPoint(x: 0, y: 1)
            sprite.position = CGPoint(x: CGFloat(command.x), y: CGFloat(322 - command.y))
            sprite.size = CGSize(width: CGFloat(command.width), height: CGFloat(command.height))
            sprite.zPosition = CGFloat(index)
            sprite.blendMode = .replace // QuickDraw srcCopy: no white/black color key.
            addChild(sprite)
            sprites.append(sprite)
        }
        isPaused = !active || modalDispatchBlocked
    }

    deinit { colorSpaceObservers.forEach(NotificationCenter.default.removeObserver) }

    override func willMove(from view: SKView) {
        colorSpaceObservers.forEach(NotificationCenter.default.removeObserver)
        colorSpaceObservers.removeAll()
        setActive(false)
    }

    private func refreshRenderingColorSpace() {
        let identifier = TextureLoader.renderingColorSpaceID(for: view)
        guard identifier != colorSpaceID else { return }
        colorSpaceID = identifier
        textures.removeAll()
        for entry in OriginalResources.manifest?.images(forResourceId: 19000) ?? [] where entry.resource.type == "Imag" {
            textures[entry.frame_index] = TextureLoader.texture(for: entry, renderingIn: view)
        }
        for (sprite, command) in zip(sprites, animation.drawCommands) {
            sprite.texture = textures[command.frame]
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard active, !modalDispatchBlocked else { return }
        refreshRenderingColorSpace()
        #if os(macOS)
        guard let window = view?.window, window.isVisible, window.occlusionState.contains(.visible) else {
            nextTick = nil
            return
        }
        #endif
        let tick = UInt64(ProcessInfo.processInfo.systemUptime * 60)
        guard tick >= (nextTick ?? tick) else { return }
        // A fresh TickCount+2 deadline after each update, never a catch-up loop.
        animation.step { OriginalRandomStream.shared.bounded($0) }
        for (sprite, command) in zip(sprites, animation.drawCommands) {
            sprite.texture = textures[command.frame]
        }
        nextTick = UInt64(ProcessInfo.processInfo.systemUptime * 60) + UInt64(OriginalTitleAnimation.tickInterval)
    }
}
