/// CODE1 sampled-sound channel and application FIFO. Native playback consumes commands.
struct OriginalAudioQueue {
    enum Command: Equatable { case start(Int), stop }
    private(set) var enabled = true
    private(set) var current: Int?
    private(set) var pending: [Int] = []
    private var callbackComplete = false
    /// Native channel status is idle as soon as completion arrives, before pump.
    var isPlaying: Bool { current != nil && !callbackComplete }

    mutating func request(_ id: Int) -> [Command] {
        guard enabled else { return [] }
        guard current == nil else { enqueue(id); return [] }
        current = id
        callbackComplete = false
        return [.start(id)]
    }
    mutating func enqueue(_ id: Int) {
        if pending.count < 8 { pending.append(id) }
    }
    mutating func completed() {
        if current != nil { callbackComplete = true }
    }
    mutating func pump() -> [Command] {
        guard current == nil || callbackComplete else { return [] }
        var commands: [Command] = []
        if callbackComplete {
            commands.append(.stop)
            current = nil
            callbackComplete = false
        }
        if !pending.isEmpty {
            let id = pending.removeFirst()
            commands += request(id)
        }
        return commands
    }
    mutating func clear() -> [Command] {
        let commands: [Command] = current == nil ? [] : [.stop]
        current = nil
        callbackComplete = false
        pending.removeAll()
        return commands
    }
    mutating func setEnabled(_ value: Bool) -> [Command] {
        enabled = value
        return value ? [] : clear()
    }
}
