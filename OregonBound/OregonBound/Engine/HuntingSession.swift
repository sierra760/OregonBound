/// Shared presentation contract; each edition retains its own mechanics.
protocol HuntingSession {
    var input: OriginalHuntSession.Input { get }
    var renderViewport: OriginalHuntSession.Rect { get }
    var palette: OriginalHuntSession.Palette { get }
    var fillCommands: [OriginalHuntSession.FillCommand] { get }
    var backgroundLine: OriginalHuntSession.FillCommand? { get }
    var drawCommands: [OriginalHuntSession.DrawCommand] { get }
    var endTick: Int { get }
    var isPaused: Bool { get }
    mutating func beginScene(random: (Int)->Int)
    mutating func setPaused(_ paused: Bool,at tick: Int)
    mutating func move()
    mutating func stop()
    mutating func advance(to tick: Int,random: (Int)->Int)
    mutating func shoot(x: Int,y: Int,at tick: Int) -> OriginalHuntSession.ShotResponse
    mutating func takeEvents() -> [OriginalHuntSession.Event]
}

extension OriginalHuntSession: HuntingSession {
    var renderViewport: Rect { Self.viewport }
    var backgroundLine: FillCommand? { nil }
    mutating func shoot(x: Int,y: Int,at tick: Int) -> ShotResponse { shoot(x: x,y: y) }
}
extension CDHuntSession: HuntingSession {
    // CODE14:15c4 clips animation at bottom268; the input user item still ends271.
    var renderViewport: Rect { .init(x: 9,y: 9,width: 494,height: 259) }
    var fillCommands: [OriginalHuntSession.FillCommand] { [] }
    var backgroundLine: OriginalHuntSession.FillCommand? {
        .init(rect: .init(x: 9,y: 267,width: 494,height: 1),rgb16: [0,0,0])
    }
}
