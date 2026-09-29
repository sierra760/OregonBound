import SpriteKit
import OSLog

private let animLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "ImagAnimator")

final class ImagAnimator: SKSpriteNode {
    let frameCount: Int
    let framesPerSecond: Double
    let resourceId: Int

    init(manifest: GraphicsManifest, resourceId: Int, fps: Double = 12.0) {
        let frames = manifest.images(forResourceId: resourceId)
        self.frameCount = frames.count
        self.framesPerSecond = fps
        self.resourceId = resourceId

        guard !frames.isEmpty else {
            animLogger.error("ImagAnimator: no frames for resource \(resourceId, privacy: .public)")
            super.init(texture: nil, color: .clear, size: .zero)
            return
        }

        let textures = TextureLoader.textures(for: frames)
        let first = frames[0]
        super.init(
            texture: textures.first,
            color: .white,
            size: CGSize(width: first.width, height: first.height)
        )

        // Reapply nearest-neighbor filtering to the node's texture in case
        // SKSpriteNode reset the setting from TextureLoader.
        texture?.filteringMode = .nearest

        if textures.count > 1 {
            let animate = SKAction.animate(with: textures, timePerFrame: 1.0 / fps)
            run(.repeatForever(animate))
        }

        animLogger.info(
            "ImagAnimator: resource \(resourceId, privacy: .public) — \(frames.count, privacy: .public) frames at \(fps, privacy: .public) fps"
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported; use init(manifest:resourceId:fps:)")
    }
}
