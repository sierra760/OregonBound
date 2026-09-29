import Foundation

/// Scpt5310 and the original CODE5 VM (0x0c62–0x0fa4).
/// Coordinates are in the original 512×322 window; viewport is (64,9,262,155).
struct OriginalRiverAnimation {
    enum Method: Int, CaseIterable { case ford = 1, caulk = 2, ferry = 3 }
    enum Outcome: Equatable { case success, failure }
    struct Instruction: Equatable {
        let offset: Int
        let size: Int
        let opcode: Int
        let arguments: [Int]
    }
    struct Object: Equatable {
        let script: Int
        var pc = 0
        var frame = 0
        var x = 0
        var y = 0
        var visible = false
        var mode = 0
        var phase = 0
        var duration = 0
        var repeatCount = 0
        var fixedX: Int32 = 0
        var fixedY: Int32 = 0
        var velocityX: Int32 = 0
        var velocityY: Int32 = 0
        var deleted = false
    }
    struct DrawCommand: Equatable {
        let object: Int
        let frame: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let masked: Bool
    }
    enum DecodeError: Error { case invalidResource }
    static let tickInterval = 3
    static let frameSizes = [(262,155),(110,73),(108,70),(53,24),(38,19),(32,27),(18,13),
                             (67,53),(65,61),(107,71),(106,68),(109,58),(98,60),(100,61),
                             (104,60),(105,66),(101,67),(105,57)]
    private let programs: [[Instruction]]
    private(set) var objects: [Object]
    private(set) var signal = 0 // A single shared scene word, NOT a set of flags.
    private(set) var updates = 0
    var isComplete: Bool { objects.isEmpty }

    init(method: Method, outcome: Outcome) {
        let variant = method == .ford ? 2 : method == .caulk ? 0 : 1
        let mainScript = variant + (outcome == .success ? 7 : 10)
        let order = outcome == .success ? [mainScript, 1, 2, 0] : [3, 4, 5, 6, mainScript, 2, 0]
        let programs = Self.originalPrograms
        self.init(programs: programs, creationOrder: programs.count == 13 ? order : [], maskedScripts: [mainScript])
        step() // CODE18:0x07e2–0x07f0 initializes once without redraw.
    }

    /// Internal initializer also permits focused VM tests independent of river outcomes.
    init(programs: [[Instruction]], creationOrder: [Int], maskedScripts: Set<Int> = []) {
        self.programs = programs
        objects = creationOrder.map { Object(script: $0, mode: maskedScripts.contains($0) ? -1 : 0) }
    }

    var drawCommands: [DrawCommand] {
        objects.reversed().compactMap { object in
            guard object.visible, !object.deleted else { return nil }
            let size = Self.frameSizes[object.frame]
            return DrawCommand(object: object.script, frame: object.frame, x: object.x, y: object.y,
                               width: size.0, height: size.1,
                               masked: object.mode == -1 && [7,9,12].contains(object.frame))
        }
    }

    mutating func step() {
        guard !isComplete else { return }
        updates += 1
        for index in objects.indices {
            var object = objects[index]
            run(&object)
            objects[index] = object
        }
        objects.removeAll(where: \.deleted) // CODE5:0x01f4–0x022a, after every object updates.
    }

    private mutating func run(_ object: inout Object) {
        var firstUpdate = true
        if object.phase != object.duration {
            object.phase += 1
            firstUpdate = false
        }
        let program = programs[object.script]
        // Each extracted program yields. The bound also rejects malformed immediate loops.
        for _ in 0..<4096 {
            guard let instruction = program.first(where: { $0.offset == object.pc }) else {
                preconditionFailure("Scpt PC is not an instruction boundary")
            }
            let args = instruction.arguments
            var continueImmediately = true
            switch instruction.opcode {
            case 0: break
            case 1: // Wait N consumes exactly N updates including its first one.
                if firstUpdate {
                    object.phase = args[0] == 0 ? 0 : 1
                    object.duration = args[0]
                }
                continueImmediately = args[0] == 0
            case 2, 3:
                continueImmediately = false
                if firstUpdate {
                    object.duration = args[0]
                    object.phase = args[0] == 0 ? 0 : 1
                    let dx = args[1] - (instruction.opcode == 3 ? object.x : 0)
                    let dy = args[2] - (instruction.opcode == 3 ? object.y : 0)
                    if args[0] == 0 {
                        object.x += dx; object.y += dy
                        continueImmediately = true
                    } else {
                        object.fixedX = Int32(object.x) << 16
                        object.fixedY = Int32(object.y) << 16
                        // Signed division truncates toward zero, as the original helper.
                        object.velocityX = (Int32(dx) << 16) / Int32(args[0])
                        object.velocityY = (Int32(dy) << 16) / Int32(args[0])
                    }
                }
                if object.duration != 0 {
                    object.fixedX = object.fixedX &+ object.velocityX
                    object.fixedY = object.fixedY &+ object.velocityY
                    object.x = Int((object.fixedX &+ 0x8000) >> 16)
                    object.y = Int((object.fixedY &+ 0x8000) >> 16)
                }
            case 4: object.frame = wrappedFrame(args[0])
            case 5: object.frame = wrappedFrame(object.frame + 1)
            case 6: object.frame = wrappedFrame(object.frame - 1)
            case 7:
                if object.repeatCount == 0 {
                    object.repeatCount = args[0]
                    object.pc = args[2] - instruction.size
                } else {
                    object.repeatCount -= 1
                    if object.repeatCount != 0 { object.pc = args[2] - instruction.size }
                }
            case 8: object.visible = false
            case 9: object.visible = true
            case 10: signal = args[0]
            case 11:
                if firstUpdate { object.phase = 1; object.duration = 1 }
                if signal != args[0] { object.phase = 0; continueImmediately = false }
            case 12: object.mode = args[0]
            case 255: object.deleted = true; continueImmediately = false
            default: preconditionFailure("Opcode is absent from original Scpt5310")
            }
            if continueImmediately {
                object.pc += instruction.size
                firstUpdate = true
            } else {
                if object.phase == object.duration { object.pc += instruction.size }
                return
            }
        }
        preconditionFailure("Scpt program did not yield")
    }

    private func wrappedFrame(_ frame: Int) -> Int {
        if frame < 0 { return frame + Self.frameSizes.count }
        if frame >= Self.frameSizes.count { return frame - Self.frameSizes.count }
        return frame
    }

    static func decode(_ data: Data) throws -> [[Instruction]] {
        let bytes = Array(data)
        func unsigned(_ at: Int, _ length: Int) -> Int {
            bytes[at..<at + length].reduce(0) { ($0 << 8) | Int($1) }
        }
        guard bytes.count >= 2 else { throw DecodeError.invalidResource }
        var cursor = 2
        var programs: [[Instruction]] = []
        let sizes = [0:2,1:4,2:8,3:8,4:4,5:2,6:2,7:8,8:2,9:2,10:4,11:4,12:4,255:2]
        for _ in 0..<unsigned(0,2) {
            guard cursor + 4 <= bytes.count else { throw DecodeError.invalidResource }
            let length = unsigned(cursor,4)
            guard length >= 6, length <= bytes.count - cursor else { throw DecodeError.invalidResource }
            let start = cursor + 4, end = cursor + length
            var pc = start
            var instructions: [Instruction] = []
            while pc < end {
                guard pc + 2 <= end else { throw DecodeError.invalidResource }
                let size = Int(bytes[pc]), opcode = Int(bytes[pc+1])
                guard sizes[opcode] == size, pc + size <= end else { throw DecodeError.invalidResource }
                let args = stride(from: pc+2, to: pc+size, by: 2).map { Int(Int16(bitPattern: UInt16(unsigned($0,2)))) }
                instructions.append(Instruction(offset: pc-start, size: size, opcode: opcode, arguments: args))
                pc += size
            }
            let boundaries = Set(instructions.map(\.offset))
            guard instructions.allSatisfy({ $0.opcode != 7 || boundaries.contains($0.arguments[2]) }) else { throw DecodeError.invalidResource }
            programs.append(instructions)
            cursor = end
        }
        guard cursor == bytes.count else { throw DecodeError.invalidResource }
        return programs
    }

    static var originalResource: Data? {
        guard let url = GameData.url(forResource: "scpt_5310", withExtension: "bin", subdirectory: "runtime") else { return nil }
        return try? Data(contentsOf: url)
    }
    static var originalPrograms: [[Instruction]] {
        guard let data = originalResource else { return [] }
        return (try? decode(data)) ?? []
    }

}

/// CODE5:0x0850 maps white to zero and other colors to one; CalcCMask fills
/// enclosed interiors. Only white connected to an outer edge is transparent.
enum OriginalRiverMask {
    static func transparentPixels(width: Int, height: Int, white: [Bool]) -> [Bool] {
        precondition(width > 0 && height > 0 && white.count == width * height)
        var exterior = [Bool](repeating: false, count: white.count)
        var queue: [Int] = []
        func enqueue(_ index: Int) {
            if white[index] && !exterior[index] { exterior[index] = true; queue.append(index) }
        }
        for x in 0..<width { enqueue(x); enqueue((height-1)*width+x) }
        for y in 0..<height { enqueue(y*width); enqueue(y*width+width-1) }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            let x = index % width, y = index / width
            if x > 0 { enqueue(index-1) }
            if x+1 < width { enqueue(index+1) }
            if y > 0 { enqueue(index-width) }
            if y+1 < height { enqueue(index+width) }
        }
        return exterior
    }
}
