import Foundation
import Testing
@testable import OregonBound

struct OriginalRiverAnimationTests {
    typealias VM = OriginalRiverAnimation
    private func program(_ operations: [(Int,[Int])]) -> [VM.Instruction] {
        var offset = 0
        return operations.map { op, args in
            let instruction = VM.Instruction(offset: offset, size: 2+args.count*2, opcode: op, arguments: args)
            offset += instruction.size
            return instruction
        }
    }

    @Test(.enabled(if: GameData.isReady)) func resourceHasExactThirteenProgramsAndRepeatTargets() throws {
        #expect(VM.originalPrograms.count == 13)
        #expect(VM.originalPrograms[9].filter { $0.opcode == 7 }.map(\.arguments) == [[3,-2,40],[3,-2,58]])
        #expect(VM.originalPrograms[12].last?.offset == 70)
        var truncated = try #require(VM.originalResource)
        truncated.removeLast()
        #expect(throws: VM.DecodeError.self) { try VM.decode(truncated) }
    }

    @Test func waitConsumesExactlyItsSpecifiedUpdatesAndZeroWaitIsImmediate() {
        var vm = VM(programs: [program([(1,[2]),(1,[0]),(10,[9]),(255,[])])], creationOrder: [0])
        vm.step(); #expect(vm.signal == 0)
        vm.step(); #expect(vm.signal == 0)
        vm.step(); #expect(vm.signal == 9); #expect(vm.isComplete)
    }

    @Test func movementAdvancesImmediatelyUsingSignedFixedPointRounding() {
        var vm = VM(programs: [program([(2,[3,-2,2]),(1,[1]),(255,[])])], creationOrder: [0])
        vm.step(); #expect(vm.objects[0].x == -1); #expect(vm.objects[0].y == 1)
        vm.step(); #expect(vm.objects[0].x == -1); #expect(vm.objects[0].y == 1)
        vm.step(); #expect(vm.objects[0].x == -2); #expect(vm.objects[0].y == 2)
        #expect(vm.objects[0].velocityX == -43690)
        vm.step(); #expect(!vm.isComplete)
        vm.step(); #expect(vm.isComplete)
    }

    @Test func signalsAreAWordAndObjectsObserveCreationOrder() {
        let sender = program([(10,[1]),(11,[2]),(255,[])])
        let receiver = program([(11,[1]),(10,[2]),(255,[])])
        var vm = VM(programs: [sender,receiver], creationOrder: [0,1])
        vm.step(); #expect(vm.signal == 2); #expect(vm.objects.map(\.script) == [0])
        vm.step(); #expect(vm.isComplete)
        let overwrite = program([(10,[3]),(255,[])])
        var lost = VM(programs: [sender,receiver,overwrite], creationOrder: [0,2,1])
        lost.step(); #expect(lost.signal == 3); #expect(lost.objects.map(\.script) == [0,1])
        lost.step(); #expect(lost.objects[1].pc == 0) // signal1 was overwritten, not latched.
    }

    @Test func repeatCountMeansAdditionalIterations() {
        // frame0; next; wait1; repeat3,target4; delete
        var vm = VM(programs: [program([(4,[0]),(5,[]),(1,[1]),(7,[3,-2,4]),(255,[])])], creationOrder: [0])
        for expected in 1...4 { vm.step(); #expect(vm.objects[0].frame == expected) }
        vm.step(); #expect(vm.isComplete)
    }

    @Test(.enabled(if: GameData.isReady)) func originalSixCrossingsFinishWithExpectedSignalTimingAndDrawOrder() {
        for method in VM.Method.allCases {
            for outcome in [VM.Outcome.success,.failure] {
                var vm = VM(method: method, outcome: outcome)
                #expect(vm.updates == 1)
                #expect(vm.drawCommands.prefix(2).map(\.frame) == [0,2])
                #expect(vm.drawCommands.last?.masked == true)
                let firstSignalUpdate = method == .ford ? 31 : method == .caulk ? 34 : 28
                while vm.updates < firstSignalUpdate-1 { vm.step() }
                #expect(vm.signal == 0)
                vm.step(); #expect(vm.signal == 1)
                while !vm.isComplete && vm.updates < 1000 { vm.step() }
                #expect(vm.isComplete); #expect(vm.signal == 6)
                let expected: Int
                switch (method,outcome) {
                case (.ford,.success): expected = 191
                case (.ford,.failure): expected = 131
                case (.caulk,.success): expected = 140
                case (.caulk,.failure),(.ferry,.failure): expected = 105
                case (.ferry,.success): expected = 129
                }
                #expect(vm.updates == expected)
            }
        }
    }

    @Test func originalMaskKeepsEnclosedWhiteAndUsesFourWayConnectivity() {
        var white = [Bool](repeating: true, count: 25)
        for y in 1...3 { for x in 1...3 { white[y*5+x] = false } }
        white[12] = true
        var mask = OriginalRiverMask.transparentPixels(width: 5,height: 5,white: white)
        #expect(mask.filter { $0 }.count == 16); #expect(mask[12] == false)
        white[6] = true // Diagonal opening does not join the center to the exterior.
        mask = OriginalRiverMask.transparentPixels(width: 5,height: 5,white: white)
        #expect(mask[12] == false)
        white[7] = true
        mask = OriginalRiverMask.transparentPixels(width: 5,height: 5,white: white)
        #expect(mask[12] == true)
    }
}
