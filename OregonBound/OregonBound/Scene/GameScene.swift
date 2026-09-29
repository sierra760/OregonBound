import SpriteKit
import OSLog

private let sceneLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "Scene")

final class GameScene: SKScene {
    /// Profession value 1–8 selected in MainMenuView; set by GameSceneContainerView before presentation.
    var profession: Int = 1

    /// Active game state initialized from newGame on scene entry.
    private(set) var gameState: GameState?

    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Seed from wall time so each play session uses a different RNG sequence.
        var rng = LCGRandomNumberGenerator(seed: UInt32(Date().timeIntervalSince1970))
        gameState = GameState.newGame(profession: profession, rng: &rng)
        sceneLogger.info(
            "GameScene: didMove — profession=\(self.profession, privacy: .public) distanceToNext=\(self.gameState?.distanceToNext ?? -1, privacy: .public)"
        )
        sceneLogger.info("GameScene: composing three-layer trail scene")

        guard let manifest = BundleAssets.loadManifest() else {
            sceneLogger.error("GameScene: failed to load graphics manifest")
            return
        }

        // z=0: Background — Imag 19030, single-frame trail map (494x304)
        if let bgImage = manifest.images(forResourceId: 19030).first,
           let bgTexture = TextureLoader.texture(for: bgImage) {
            let background = SKSpriteNode(texture: bgTexture)
            background.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            background.position = CGPoint(x: size.width / 2, y: size.height / 2)
            background.zPosition = 0
            background.name = "background"
            addChild(background)
            sceneLogger.info("GameScene: background — Imag 19030 \(bgImage.width, privacy: .public)x\(bgImage.height, privacy: .public)")
        } else {
            sceneLogger.error("GameScene: failed to load background Imag 19030")
        }

        // z=1: Wagon animation — Imag 19000, 47 frames at 12 fps
        let wagon = ImagAnimator(manifest: manifest, resourceId: 19000, fps: 12.0)
        wagon.position = CGPoint(x: size.width / 2, y: size.height / 2)
        wagon.zPosition = 1
        wagon.name = "wagon"
        addChild(wagon)
        sceneLogger.info("GameScene: wagon — Imag 19000 \(wagon.frameCount, privacy: .public) frames at \(wagon.framesPerSecond, privacy: .public) fps")

        // z=2: HUD icon — cicn 5000 (oxen icon, 32x32), top-left corner
        if let hudImage = manifest.firstImage(ofType: "cicn", resourceId: 5000),
           let hudTexture = TextureLoader.texture(for: hudImage) {
            let hudIcon = SKSpriteNode(texture: hudTexture)
            hudIcon.position = CGPoint(x: 32, y: size.height - 32)
            hudIcon.zPosition = 2
            hudIcon.name = "hudIcon"
            addChild(hudIcon)
            sceneLogger.info("GameScene: hudIcon — cicn 5000 \(hudImage.width, privacy: .public)x\(hudImage.height, privacy: .public)")
        } else {
            sceneLogger.error("GameScene: failed to load HUD icon cicn 5000")
        }

        sceneLogger.info("GameScene: scene composed — background(Imag 19030) + wagon(Imag 19000, \(manifest.images(forResourceId: 19000).count, privacy: .public) frames) + hudIcon(cicn 5000)")
    }

    override func update(_ currentTime: TimeInterval) {}
}
