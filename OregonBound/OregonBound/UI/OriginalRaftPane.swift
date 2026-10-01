import SwiftUI
import Combine

/// DITL9201 → CODE17 game user item → DITL9202. Completion hands off actual losses.
struct OriginalRaftPane: View {
    let input: OriginalRaftSession.Input
    let random: OriginalRandomStream
    let audio: GameAudio
    private let edition: GameEdition
    @State private var preparedAudio = false
    let onSceneCreated: (OriginalRaftScene) -> Void
    let onLand: (OriginalRaftSession.Result)->Void
    let onSubmit: (OriginalRaftSession.Result)->Void
    let onFinish: (OriginalRaftSession.Result)->Void
    @State private var scene: OriginalRaftScene?
    @State private var result: OriginalRaftSession.Result?
    @State private var presentation = OriginalRaftPresentation()
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0/60,on: .main,in: .common).autoconnect()

    init(input: OriginalRaftSession.Input,random: OriginalRandomStream, audio: GameAudio = .shared,
         onSceneCreated: @escaping (OriginalRaftScene) -> Void = { _ in },
         onLand: @escaping (OriginalRaftSession.Result)->Void = { _ in },
         onSubmit: @escaping (OriginalRaftSession.Result)->Void = { _ in },
         onFinish: @escaping (OriginalRaftSession.Result)->Void) {
        self.onSceneCreated = onSceneCreated
        self.audio = audio; self.edition = GameData.edition
        self.input = input; self.random = random; self.onLand = onLand; self.onSubmit = onSubmit; self.onFinish = onFinish
    }
    init(input: OriginalRaftSession.Input,seed: UInt32,
         onFinish: @escaping (OriginalRaftSession.Result,UInt32)->Void) {
        let stream = OriginalRandomStream(seed: seed)
        self.init(input: input,random: stream) { result in onFinish(result,stream.seed) }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if let result, result.survivors > 0 {
                OriginalDialogContents(resource: 9202,substitutions: ["Pulling up onshore"]) { _ in }
            } else if let scene {
                OriginalRaftArtwork(scene: scene)
            } else {
                OriginalDialogContents(resource: 9201) { _ in }
            }
        }.frame(width: 494,height: 304)
            .onAppear {
                visible = true
                if !preparedAudio {
                    preparedAudio = true
                    if edition == .macintoshCD12 { audio.clear() }
                }
                if !modalBlocked { _ = presentation.advance(to: tick,active: scenePhase == .active) }
            }
            .onDisappear { visible = false; _ = presentation.advance(to: tick,active: false) }
            .onChange(of: scenePhase) { _ in _ = presentation.advance(to: tick,active: false) }
            .onReceive(timer) { _ in
                guard !modalBlocked else { return }
                switch presentation.advance(to: tick,active: visible && scenePhase == .active) {
                case .beginRafting:
                    let created = OriginalRaftScene(input: input,random: random, audio: audio) { value in
                        onLand(value); result = value; presentation.raftingFinished(survivors: value.survivors)
                    }
                    scene = created
                    onSceneCreated(created)
                case .submitLosses:
                    if let result { onSubmit(result) }
                case .complete:
                    if let result {
                        if result.survivors == 0 { onSubmit(result) }
                        onFinish(result)
                    }
                case nil: break
                }
            }
    }
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime*60) }
}
