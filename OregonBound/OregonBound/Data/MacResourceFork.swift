import Foundation

/// One resource from a classic Macintosh resource fork. `data` is the stored
/// bytes: System 7 compressed resources (attribute bit 0) are not expanded here.
struct MacResource: Equatable {
    let type: String
    let id: Int
    let name: String?
    let attributes: UInt8
    let data: Data
    var isCompressed: Bool { attributes & 1 != 0 }
}

/// Parsed resource map of a resource fork (Inside Macintosh: More Macintosh Toolbox, 1-121).
struct MacResourceFork {
    enum Failure: Error, CustomStringConvertible {
        case invalidHeader(String)
        var description: String {
            switch self { case .invalidHeader(let reason): return "Not a resource fork: \(reason)" }
        }
    }

    let resources: [MacResource]
    private let index: [String: [Int: MacResource]]

    init(resources: [MacResource]) {
        self.resources = resources
        var index: [String: [Int: MacResource]] = [:]
        for resource in resources where index[resource.type]?[resource.id] == nil {
            index[resource.type, default: [:]][resource.id] = resource
        }
        self.index = index
    }

    init(data: Data) throws {
        let reader = BinaryReader(data)
        guard reader.count >= 16 else { throw Failure.invalidHeader("shorter than the 16-byte header") }
        let dataOffset = Int(try reader.u32(0))
        let mapOffset = Int(try reader.u32(4))
        let dataLength = Int(try reader.u32(8))
        let mapLength = Int(try reader.u32(12))
        guard dataOffset >= 16, mapOffset >= 16, mapLength >= 30,
              dataOffset + dataLength <= reader.count, mapOffset + mapLength <= reader.count else {
            throw Failure.invalidHeader("header offsets exceed the fork length")
        }
        let typeListOffset = mapOffset + Int(try reader.u16(mapOffset + 24))
        let nameListOffset = mapOffset + Int(try reader.u16(mapOffset + 26))
        let typeCountField = try reader.u16(mapOffset + 28)
        var resources: [MacResource] = []
        if typeCountField != 0xffff {
            let typeCount = Int(typeCountField) + 1
            for typeIndex in 0..<typeCount {
                let entry = typeListOffset + 2 + typeIndex * 8
                let typeCode = MacRoman.decode(try reader.slice(entry, 4))
                let count = Int(try reader.u16(entry + 4)) + 1
                let referenceList = typeListOffset + Int(try reader.u16(entry + 6))
                for referenceIndex in 0..<count {
                    let reference = referenceList + referenceIndex * 12
                    let id = Int(try reader.i16(reference))
                    let nameOffset = try reader.u16(reference + 2)
                    let mixed = try reader.u32(reference + 4)
                    let attributes = UInt8(mixed >> 24)
                    let resourceDataOffset = dataOffset + Int(mixed & 0xffffff)
                    let resourceLength = Int(try reader.u32(resourceDataOffset))
                    let payload = try reader.data(resourceDataOffset + 4, resourceLength)
                    var name: String?
                    if nameOffset != 0xffff {
                        name = try reader.pascalString(nameListOffset + Int(nameOffset)).text
                    }
                    resources.append(MacResource(type: typeCode, id: id, name: name, attributes: attributes, data: payload))
                }
            }
        }
        self.init(resources: resources)
    }

    subscript(type: String, id: Int) -> MacResource? { index[type]?[id] }
    func resources(ofType type: String) -> [MacResource] {
        resources.filter { $0.type == type }.sorted { $0.id < $1.id }
    }
    func contains(_ type: String) -> Bool { index[type] != nil }
    var types: Set<String> { Set(index.keys) }
}
