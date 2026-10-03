import SwiftUI
import XCTest
@testable import OregonBound

@MainActor final class OriginalModalSceneTests: XCTestCase {
    func testEnvironmentDefaultsToDispatchingAndCanBlock() {
        var environment = EnvironmentValues()
        XCTAssertTrue(!environment.originalModalDispatchBlocked)
        environment.originalModalDispatchBlocked = true
        XCTAssertTrue(environment.originalModalDispatchBlocked)
    }

    func testModalHookDoesNotUseHuntClockPauseOrConsumeRandomDraws() throws {
        let input = OriginalHuntSession.Input(destination: 2,month: 4,weatherCategory: 0,
            snow: false,mileage: 20,lastSuccessfulHuntMileage: 20,ammunition: 99,
            survivors: 5,currentFood: 0,foodCapacity: 2000,timeSetting: 1,originalDisplayFlag: false)
        let random = OriginalRandomStream(seed: 1234)
        let scene = try OriginalHuntScene(input: input,random: random) { _ in }
        scene.setActive(true)
        let deadline = scene.session.endTick, seed = random.seed
        scene.setModalDispatchBlocked(true)
        scene.update(1_000_000)
        XCTAssertTrue(scene.isPaused && !scene.session.isPaused)
        XCTAssertTrue(scene.session.endTick == deadline && random.seed == seed)
        scene.setModalDispatchBlocked(false)
        XCTAssertTrue(!scene.isPaused && !scene.session.isPaused)
        XCTAssertTrue(scene.session.endTick == deadline && random.seed == seed)
    }
}

#if os(macOS)
import AppKit
import SpriteKit

@MainActor final class OriginalTitleLaunchTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var phase: ScenePhase = .inactive
        @Published var blocked = false
    }
    private struct Harness: View {
        @ObservedObject var model: Model
        var body: some View {
            OriginalTitleArtwork().environment(\.scenePhase, model.phase)
                .environment(\.originalModalDispatchBlocked, model.blocked)
        }
    }
    private func spriteView(in view: NSView) -> SKView? {
        if let sprite = view as? SKView { return sprite }
        return view.subviews.lazy.compactMap { self.spriteView(in: $0) }.first
    }
    func testTitleStartsAfterLaunchActivationWithoutResize() async throws {
        try GameDataTestSupport.requireGameData()
        let model = Model()
        let host = NSHostingView(rootView: Harness(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 494, height: 304),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let sprite = try XCTUnwrap(spriteView(in: host))
        model.phase = .active
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(sprite.isPaused, "The title renderer must run without a resize")
        let scene = try XCTUnwrap(sprite.scene)
        XCTAssertFalse(scene.isPaused)
        XCTAssertFalse(scene.children.isEmpty)
        XCTAssertEqual(scene.size, CGSize(width: 512, height: 322))
        model.blocked = true
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(sprite.isPaused)
        model.blocked = false
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(sprite.isPaused)
        model.phase = .inactive
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(sprite.isPaused)
        model.phase = .active
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(sprite.isPaused)
    }
}
#endif
