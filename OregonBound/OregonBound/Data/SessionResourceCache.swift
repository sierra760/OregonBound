import Foundation

/// A new session invalidates successful loads and cached misses alike.
final class SessionResourceCache<Key: Hashable, Value> {
    private enum Entry { case loaded(Value?) }
    private var identity: UUID?
    private var entries: [Key: Entry] = [:]
    private let lock = NSLock()

    func value(for key: Key, session: UUID, load: () -> Value?) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        if identity != session { entries.removeAll(); identity = session }
        if case .loaded(let value) = entries[key] { return value }
        let value = load()
        entries[key] = .loaded(value)
        return value
    }
}
