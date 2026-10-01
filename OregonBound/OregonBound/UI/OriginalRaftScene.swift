import ImageIO
import SpriteKit
import SwiftUI

/// CODE17's original 494×304 user item, cropped from full-window coordinates.
struct OriginalRaftArtwork: View {
    let scene: OriginalRaftScene
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    var body: some View {
        SpriteView(scene: scene,isPaused: !visible || scenePhase != .active || modalBlocked,preferredFramesPerSecond: 60)
            .frame(width: 512,height: 322)
            .offset(x: -OriginalWindowLayout.contentOrigin.x, y: -OriginalWindowLayout.contentOrigin.y)
            .frame(width: 494,height: 304,alignment: .topLeading).clipped()
            .accessibilityLabel("Raft down the Columbia River. Move the mouse to avoid rocks.")
            .onAppear { visible = true; scene.setModalDispatchBlocked(modalBlocked); scene.setActive(scenePhase == .active) }
            .onChange(of: scenePhase) { phase in scene.setActive(visible && phase == .active) }
            .onChange(of: modalBlocked) { value in scene.setModalDispatchBlocked(value) }
            .onDisappear { visible = false; scene.setActive(false) }
    }
}

@MainActor final class OriginalRaftScene: SKScene {
    private(set) var session: OriginalRaftSession
    private let random: OriginalRandomStream
    private let completion: (OriginalRaftSession.Result)->Void
    private var active = false
    private var modalDispatchBlocked = false
    private var completed = false
    private var pendingCompletion: OriginalRaftSession.Result?
    private var touchX: Int?
    #if os(macOS)
    private var mouseEvents: Any?
    private weak var mouseWindow: NSWindow?
    private var previousAcceptsMouseMoved = false
    private var eventMouseX: Int?
    private var previousPolledMouseX: Int?
    #endif
    private let artwork = SKNode()
    private let lossPanel = SKNode()
    private var textures: [String:SKTexture] = [:]
    private var colorSpaceID: String?
    private var observers: [NSObjectProtocol] = []
    private static var tick: Int { Int(ProcessInfo.processInfo.systemUptime*60) }

    init(input: OriginalRaftSession.Input, random: OriginalRandomStream,
         onFinish: @escaping (OriginalRaftSession.Result) -> Void) {
        let tick = Self.tick
        var displayInput = input
        if GameData.edition == .macintoshCD12 {
            // Depth is a property of the current display, not the saved wagon.
            // CODE18:0580 advances monochrome progress once, color twice.
            displayInput.pixelDepth = OriginalResources.colorMode.imageDepth.rawValue
        }
        session = OriginalRaftSession(input: displayInput,startTick: tick,edition: GameData.edition) { random.bounded($0) }
        session.setPaused(true,at: tick)
        self.random = random
        completion = onFinish
        super.init(size: CGSize(width: 512,height: 322))
        scaleMode = .fill; backgroundColor = .black; isUserInteractionEnabled = true
        addChild(artwork); lossPanel.zPosition = 1000; addChild(lossPanel)
    }
    convenience init(input: OriginalRaftSession.Input,seed: UInt32,
                     onFinish: @escaping (OriginalRaftSession.Result,UInt32)->Void) {
        let stream = OriginalRandomStream(seed: seed)
        self.init(input: input,random: stream) { result in onFinish(result,stream.seed) }
    }
    required init?(coder: NSCoder) { fatalError("OriginalRaftScene is created programmatically") }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        #if os(macOS)
        if let mouseEvents { NSEvent.removeMonitor(mouseEvents) }
        let window = mouseWindow, previous = previousAcceptsMouseMoved
        Task { @MainActor [weak window] in window?.acceptsMouseMovedEvents = previous }
        #endif
    }
    /// Unlike native application suspension, a classic modal only skips idle calls.
    func setModalDispatchBlocked(_ value: Bool) {
        modalDispatchBlocked = value
        isPaused = !active || value
    }
    func setActive(_ value: Bool) {
        active = value; session.setPaused(!value,at: Self.tick); isPaused = !value || modalDispatchBlocked
    }
    override func didMove(to view: SKView) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = TextureLoader.observeRenderingColorSpace(in: view) { [weak self] in self?.render() }
        #if os(macOS)
        installMouseEvents(in: view)
        #endif
        render(); isPaused = !active || modalDispatchBlocked
    }
    override func willMove(from view: SKView) {
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll(); setActive(false)
        #if os(macOS)
        removeMouseEvents()
        #endif
    }
    override func update(_ currentTime: TimeInterval) {
        guard active, !modalDispatchBlocked else { return }
        deliverPendingCompletion()
        guard !completed else { return }
        let tick = Self.tick
        var x = touchX
        #if os(macOS)
        guard let view, let window = view.window, window.isVisible, window.occlusionState.contains(.visible) else {
            session.setPaused(true,at: tick); return
        }
        if mouseWindow !== window { installMouseEvents(in: view) }
        if window.isKeyWindow {
            let p = view.convert(window.mouseLocationOutsideOfEventStream,from: nil)
            let polled = Int(convertPoint(fromView: p).x)
            // Synthetic events may not move the hardware cursor. Preserve their
            // coordinate until the actual polled pointer changes, including outside
            // the view/window where no local mouseMoved event may be delivered.
            if previousPolledMouseX != polled { eventMouseX = nil }
            previousPolledMouseX = polled
            x = eventMouseX ?? polled
        }
        #endif
        session.setPaused(false,at: tick)
        let stream = random
        session.advance(to: tick,mouseX: x) { stream.bounded($0) }
        render()
        for event in session.takeEvents() {
            switch event {
            case .collision(let collision):
                GameAudio.shared.clear(); GameAudio.shared.request(9006)
                if !collision.drownedMembers.isEmpty { GameAudio.shared.request(9001) }
            case .finished(let result):
                completed = true
                DispatchQueue.main.async { [weak self] in
                    self?.pendingCompletion = result
                    self?.deliverPendingCompletion()
                }
            }
        }
    }
    private func deliverPendingCompletion() {
        guard active, !modalDispatchBlocked, let result = pendingCompletion else { return }
        pendingCompletion = nil
        completion(result)
    }
    #if os(macOS)
    private func recordMouse(_ event: NSEvent) {
        guard active, !modalDispatchBlocked, let view, let window = view.window, event.window === window else { return }
        eventMouseX = Int(convertPoint(fromView: view.convert(event.locationInWindow,from: nil)).x)
        let actual = view.convert(window.mouseLocationOutsideOfEventStream,from: nil)
        previousPolledMouseX = Int(convertPoint(fromView: actual).x)
    }
    private func installMouseEvents(in view: SKView) {
        removeMouseEvents()
        guard let window = view.window else { return }
        mouseWindow = window
        previousAcceptsMouseMoved = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        mouseEvents = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown]) { [weak self] event in
            self?.recordMouse(event)
            return event
        }
    }
    private func removeMouseEvents() {
        if let mouseEvents { NSEvent.removeMonitor(mouseEvents) }
        mouseEvents = nil
        mouseWindow?.acceptsMouseMovedEvents = previousAcceptsMouseMoved
        mouseWindow = nil
    }
    override func mouseMoved(with event: NSEvent) { recordMouse(event) }
    override func mouseDragged(with event: NSEvent) { recordMouse(event) }
    override func mouseDown(with event: NSEvent) {
        guard active, !modalDispatchBlocked else { return }
        recordMouse(event); session.dismissCollision()
    }
    #else
    override func touchesBegan(_ touches: Set<UITouch>,with event: UIEvent?) {
        guard active, !modalDispatchBlocked else { return }
        session.dismissCollision(); if let point = touches.first?.location(in: self) { touchX = Int(point.x) }
    }
    override func touchesMoved(_ touches: Set<UITouch>,with event: UIEvent?) {
        guard active, !modalDispatchBlocked else { return }
        if let point = touches.first?.location(in: self) { touchX = Int(point.x) }
    }
    #endif
    private func rectangle(_ rect: CGRect,rgb: [Int],in parent: SKNode) {
        guard let image = OriginalHuntImage.solid(rgb16: rgb) else { return }
        let node = SKSpriteNode(texture: TextureLoader.texture(cgImage: image,renderingIn: view))
        node.anchorPoint = CGPoint(x: 0,y: 1); node.position = CGPoint(x: rect.minX,y: 322-rect.minY)
        node.size = rect.size; node.blendMode = .replace; parent.addChild(node)
    }
    private func render() {
        let profile = TextureLoader.renderingColorSpaceID(for: view)
        if profile != colorSpaceID { colorSpaceID = profile; textures.removeAll() }
        artwork.removeAllChildren(); lossPanel.removeAllChildren()
        // CODE17:173a–1838; literal RGBColor globals from CODE21.
        rectangle(CGRect(x: 88,y: 9,width: 239,height: 27),rgb: [9728,51456,65280],in: artwork)
        rectangle(CGRect(x: 9,y: 36,width: 405,height: 277),rgb: [0,0,65280],in: artwork)
        rectangle(CGRect(x: 415,y: 9,width: 1,height: 304),rgb: [65280,63085,35223],in: artwork)
        rectangle(CGRect(x: 414,y: 9,width: 1,height: 304),rgb: [0,0,0],in: artwork)
        for command in session.drawCommands {
            let node = SKSpriteNode(texture: texture(command))
            node.anchorPoint = CGPoint(x: 0,y: 1)
            node.position = CGPoint(x: command.x+(command.mirrored ? command.width : 0),y: 322-command.y)
            node.size = CGSize(width: command.width,height: command.height)
            node.xScale = command.mirrored ? -1 : 1
            node.blendMode = command.masked ? .alpha : .replace
            artwork.addChild(node)
        }
        if let collision = session.collision { drawLoss(collision) }
    }
    private func texture(_ command: OriginalRaftSession.DrawCommand) -> SKTexture? {
        let key = "\(command.resource):\(command.frame):\(command.masked)"
        if let cached = textures[key] { return cached }
        guard let entry = OriginalResources.frames(command.resource)
            .first(where: { $0.frame_index == command.frame }),
              let url = GameData.resourceURL(entry.image_path),
              let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil),
              let prepared = command.masked ? OriginalRiverScene.maskedImage(image) : image else { return nil }
        let value = TextureLoader.texture(cgImage: prepared,renderingIn: view); textures[key] = value; return value
    }
    private func text(_ value: String,x: Int,baseline: Int,font: BitmapFont) {
        for glyph in font.layout(value).glyphs {
            let node = SKSpriteNode(texture: TextureLoader.texture(cgImage: glyph.image,renderingIn: view))
            node.anchorPoint = CGPoint(x: 0,y: 1)
            node.position = CGPoint(x: CGFloat(x)+glyph.rect.minX,
                                    y: 322-CGFloat(baseline-font.metrics.header.ascent)-glyph.rect.minY)
            node.size = glyph.rect.size; lossPanel.addChild(node)
        }
    }
    /// CODE17:19a6. Both borders and all text are original integer coordinates.
    private func drawLoss(_ collision: OriginalRaftSession.Collision) {
        let paper = [65280,63085,35223]
        rectangle(CGRect(x: 9,y: 150,width: 405,height: 150),rgb: [0,0,0],in: lossPanel)
        rectangle(CGRect(x: 10,y: 151,width: 403,height: 148),rgb: paper,in: lossPanel)
        rectangle(CGRect(x: 12,y: 153,width: 399,height: 144),rgb: [0,0,0],in: lossPanel)
        rectangle(CGRect(x: 14,y: 155,width: 395,height: 140),rgb: paper,in: lossPanel)
        guard let font = BitmapFont.bold12 else { return }
        let strings = OriginalResources.strings(3021)
        guard strings.count >= 8 else { return }
        let height = font.lineHeight
        let baseline = 166+height
        if collision.losses.allSatisfy({ $0 == 0 }) && collision.drownedMembers.isEmpty {
            text(strings[4],x: 25,baseline: baseline,font: font)
            text(strings[5],x: 25,baseline: baseline+height,font: font); return
        }
        text(strings[6],x: 25,baseline: baseline,font: font)
        let labels = OriginalResources.strings(3011)
        var lines: [String] = []
        let itemCount = Inventory.itemCount(for: session.edition)
        for (i,raw) in collision.losses.enumerated() where raw != 0 && labels.count >= itemCount * 2 {
            let quantity = i == 0 ? (raw+1)/2 : raw
            lines.append("\(quantity) \(labels[i+(quantity == 1 ? itemCount : 0)])")
        }
        // Display leader first even though the random helper tests the leader last.
        for member in collision.drownedMembers.sorted() {
            lines.append(session.input.names[member]+strings[7])
        }
        var x = 45, y = baseline+height
        for line in lines {
            text(line,x: x,baseline: y,font: font); y += height
            if y > 294 { x += 200; y = baseline+height }
        }
    }
}
