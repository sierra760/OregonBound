/// CODE19:0c54–0c6c and CODE3:232c–2344 install default1/cancel0.
/// CODE1:1bd8–1c7c suppresses repeat defaults and checks Command before Return.
enum OriginalGameDefaultKeyRules {
    enum EventKind { case down, up, other }
    enum Action: Equatable { case passThrough, consume, activate }

    static func action(kind: EventKind, character: UInt8?, command: Bool,
                       repeating: Bool) -> Action {
        guard !command, character == 13 || character == 3 else { return .passThrough }
        switch kind {
        case .down: return repeating ? .consume : .activate
        // Native containment only: no default action is emitted for a release.
        case .up: return .consume
        case .other: return .passThrough
        }
    }
}
