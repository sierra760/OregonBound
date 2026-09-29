import Testing
@testable import OregonBound

struct OriginalGameDefaultKeyRulesTests {
    @Test func onlyOriginalDefaultCharactersActivate() {
        for byte in UInt8.min...UInt8.max {
            #expect(OriginalGameDefaultKeyRules.action(kind: .down, character: byte,
                    command: false, repeating: false) == ([3, 13].contains(byte) ? .activate : .passThrough))
        }
    }
    @Test func commandAndNonKeyEventsNeverActivate() {
        for byte: UInt8 in [3, 13, 27, 46] {
            #expect(OriginalGameDefaultKeyRules.action(kind: .down, character: byte,
                    command: true, repeating: false) == .passThrough)
            #expect(OriginalGameDefaultKeyRules.action(kind: .other, character: byte,
                    command: false, repeating: false) == .passThrough)
        }
    }
}

#if os(macOS)
import AppKit

@MainActor struct OriginalGameDefaultKeyDeliveryTests {
    private func key(_ text: String = "\r", type: NSEvent.EventType = .keyDown,
                     modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false,
                     window: Int = 47, keyCode: UInt16 = 36) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
            timestamp: 1, windowNumber: window, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: repeatKey, keyCode: keyCode))
    }

    @Test func actualReturnAndKeypadEnterActivateOncePerPresentation() throws {
        for (text, code): (String, UInt16) in [("\r", 36), ("\u{3}", 76)] {
            let delivery = OriginalGameDefaultKeyDelivery()
            var calls = 0
            let event = try key(text, keyCode: code)
            #expect(delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true,
                                    enabled: true) { calls += 1 } == nil)
            // A queued second non-repeat cannot double-dismiss while SwiftUI
            // still retains the outgoing overlay (including reentrant callbacks).
            #expect(delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true,
                                    enabled: true) { calls += 1 } == nil)
            #expect(calls == 1 && delivery.didActivate)
        }
    }

    @Test func reentrantDeliveryCannotInvokeDefaultTwice() throws {
        let delivery = OriginalGameDefaultKeyDelivery()
        let event = try key()
        var calls = 0
        _ = delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true, enabled: true) {
            calls += 1
            #expect(delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true,
                                    enabled: true) { calls += 1 } == nil)
        }
        #expect(calls == 1)
    }

    @Test func repeatsAndReleasesAreConsumedWithoutDefault() throws {
        let delivery = OriginalGameDefaultKeyDelivery()
        var calls = 0
        for event in [try key(repeatKey: true), try key(type: .keyUp)] {
            #expect(delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true,
                                    enabled: true) { calls += 1 } == nil)
        }
        #expect(calls == 0 && !delivery.didActivate)
        _ = delivery.deliver(try key(), ownerWindowNumber: 47, ownerIsKey: true,
                             enabled: true) { calls += 1 }
        #expect(calls == 1)
    }

    @Test func disabledDetachedInactiveAndForeignWindowEventsRemainUndelivered() throws {
        let delivery = OriginalGameDefaultKeyDelivery()
        let event = try key()
        var calls = 0
        for (window, active, enabled): (Int?, Bool, Bool) in [
            (nil, true, true), (48, true, true), (47, false, true), (47, true, false)
        ] {
            #expect(delivery.deliver(event, ownerWindowNumber: window, ownerIsKey: active,
                                    enabled: enabled) { calls += 1 } === event)
        }
        #expect(calls == 0 && !delivery.didActivate)
    }

    @Test func commandMenuKeysEscapeAndOrdinaryTextPassUnchanged() throws {
        let delivery = OriginalGameDefaultKeyDelivery()
        var calls = 0
        for event in [try key(modifiers: .command), try key("\u{3}", modifiers: .command),
                      try key(".", modifiers: .command), try key("\u{1b}"), try key("x"),
                      try key("x", keyCode: 76), try key("é")] {
            #expect(delivery.deliver(event, ownerWindowNumber: 47, ownerIsKey: true,
                                    enabled: true) { calls += 1 } === event)
        }
        #expect(calls == 0)
    }

    @Test func shiftOptionControlDoNotBlockOriginalDefault() throws {
        for modifiers: NSEvent.ModifierFlags in [.shift, .option, .control, [.shift, .option, .control]] {
            let delivery = OriginalGameDefaultKeyDelivery()
            var calls = 0
            #expect(delivery.deliver(try key(modifiers: modifiers), ownerWindowNumber: 47,
                                    ownerIsKey: true, enabled: true) { calls += 1 } == nil)
            #expect(calls == 1)
        }
    }
}
#endif
