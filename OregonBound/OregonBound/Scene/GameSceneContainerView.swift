import SwiftUI
import SpriteKit

struct GameSceneContainerView {
    let profession: Int
    let difficulty: Int

    init(profession: Int = 1, difficulty: Int = 1) {
        self.profession = profession
        self.difficulty = difficulty
    }

    private func makeScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        scene.scaleMode = .aspectFill
        scene.profession = profession
        return scene
    }
}

#if os(macOS)
extension GameSceneContainerView: NSViewRepresentable {
    func makeNSView(context: Context) -> SKView {
        let skView = SKView()
        skView.presentScene(makeScene())
        return skView
    }

    func updateNSView(_ nsView: SKView, context: Context) {}
}
#else
extension GameSceneContainerView: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.presentScene(makeScene())
        return skView
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}
#endif
