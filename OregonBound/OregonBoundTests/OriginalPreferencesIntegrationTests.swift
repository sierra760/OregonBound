import Foundation
import Testing
@testable import OregonBound

struct OriginalPreferencesIntegrationTests {
    @Test @MainActor func inactiveGameWindowCannotOpenManagementAndRegainsCommandsOnActivation() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        controller.fileMenu.activateWindow(false, stage: .attract)
        controller.openManagement(.about)
        #expect(controller.managementPane == nil)
        controller.managementPane = nil
        controller.fileMenu.activateWindow(true, stage: .attract)
        controller.openManagement(.about)
        #expect(controller.managementPane == .about)
    }

    @Test @MainActor func gameMenuActionsRespectFocusAndNestedModalState() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        defer { controller.sound = true }
        controller.fileMenu.activateWindow(false, stage: .attract)
        controller.requestIntroduction()
        controller.setSoundFromMenu(false)
        #expect(!controller.showingIntroduction && controller.sound && !controller.canUseGameMenus)
        controller.fileMenu.activateWindow(true, stage: .attract)
        #expect(controller.canUseGameMenus)
        controller.setSoundFromMenu(false)
        #expect(!controller.sound)
        controller.requestIntroduction()
        #expect(controller.showingIntroduction && !controller.canUseGameMenus)
        controller.setSoundFromMenu(true)
        controller.openManagement(.about)
        #expect(!controller.sound && controller.managementPane == nil)
        controller.showingIntroduction = false
        controller.setSoundFromMenu(true)
        #expect(controller.sound && controller.canUseGameMenus)
    }

    @Test @MainActor func timingPersistsSeparatelyAndExistingWorldKeepsItsSnapshot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        let controller = GameController(store: store, random: OriginalRandomStream(seed: 41))
        controller.openManagement(.timeOptions)
        #expect(controller.managementPane == nil)
        controller.start(profession: .banker, difficulty: .greenhorn, names: ["A"], month: 4)
        #expect(controller.trip?.timing.speed == .medium)
        #expect(controller.enableManagement(password: "BOOM"))
        try controller.saveTiming(.init(speed: .fast, huntTime: .minutes2))
        #expect(controller.trip?.timing.speed == .medium)
        #expect(try store.load().timing.speed == .medium)
        let relaunched = GameController(store: store, random: OriginalRandomStream(seed: 42))
        #expect(!relaunched.management.enabled)
        #expect(relaunched.preferences.timing.speed == .fast)
        relaunched.resume()
        #expect(relaunched.trip?.timing.huntTime == .seconds45)
        relaunched.start(profession: .banker, difficulty: .greenhorn, names: ["B"], month: 4)
        #expect(relaunched.trip?.timing == .init(speed: .fast, huntTime: .minutes2))
    }
    @Test func legacyWorldUsesOriginalDefaultsAndInvalidPreferencesRecover() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        try store.save(Journey(seed: 41))
        #expect(try store.load().originalTiming == nil)
        #expect(try store.load().timing == .init())
        try Data("invalid".utf8).write(to: folder.appendingPathComponent("preferences.json"))
        #expect(try store.preferences() == .init())
    }
    @Test @MainActor func fastTimerAdvancesOnSecondPulse() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41)
        trip.phase = .travel; trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        trip.originalTiming = .init(speed: .fast, huntTime: .seconds20)
        JourneyEngine.resumeTravel(in: &trip)
        controller.trip = trip
        controller.tick()
        #expect(controller.trip?.daysElapsed == 0)
        controller.tick()
        #expect(controller.trip?.daysElapsed == 1)
    }
}
