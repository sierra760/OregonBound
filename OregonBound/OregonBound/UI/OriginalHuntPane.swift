import SwiftUI
import Combine

/// DITL9160, local to OriginalWindow's 494×304 content area.
struct OriginalHuntPane: View {
    @StateObject private var scene: OriginalHuntScene
    @State private var preparation = OriginalHuntPreparation()
    @State private var visible = false
    @State private var started = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.originalModalDispatchBlocked) private var modalBlocked
    private let timer = Timer.publish(every: 1.0/60,on: .main,in: .common).autoconnect()
    private var tick: Int { Int(ProcessInfo.processInfo.systemUptime*60) }

    init(input: OriginalHuntSession.Input,random: OriginalRandomStream,
         onFinish: @escaping (OriginalHuntSession.Result)->Void) {
        var colorInput = input
        colorInput.originalDisplayFlag = true
        _scene = StateObject(wrappedValue: OriginalHuntScene(input: colorInput,random: random,onFinish: onFinish))
    }
    init(input: OriginalHuntSession.Input,seed: UInt32,
         onFinish: @escaping (OriginalHuntSession.Result,UInt32)->Void) {
        let stream = OriginalRandomStream(seed: seed)
        self.init(input: input,random: stream) { result in onFinish(result,stream.seed) }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if preparation.isReady {
            OriginalHuntArtwork(scene: scene)
            OriginalButton(title: "Move") { scene.move() }
                .frame(width: 109, height: 27).offset(x: 95, y: 270)
            OriginalButton(title: "Stop Hunting") { scene.stop() }
                .frame(width: 109, height: 27).offset(x: 296, y: 270)
            } else {
                OriginalDialogContents(resource: 9161) { _ in }
            }
        }.frame(width: 494, height: 304)
            .onAppear {
                visible = true
                if !modalBlocked { preparation.advance(to: tick,active: scenePhase == .active) }
                if !modalBlocked && !started { started = true; scene.prepareSound() }
            }
            .onDisappear { visible = false; preparation.advance(to: tick,active: false) }
            .onChange(of: scenePhase) { _ in preparation.advance(to: tick,active: false) }
            .onReceive(timer) { _ in
                guard !modalBlocked else { return }
                guard !preparation.isReady else { return }
                if !started { started = true; scene.prepareSound() }
                preparation.advance(to: tick,active: visible && scenePhase == .active)
            }
    }
}
