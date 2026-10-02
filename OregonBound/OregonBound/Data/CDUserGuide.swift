import Foundation

/// The CD's separate MECC Reader document. Its picture resources contain the
/// player's text and artwork; links address paper coordinates, not picture bounds.
struct CDUserGuide {
    struct Rect: Equatable {
        let top: Int
        let left: Int
        let bottom: Int
        let right: Int
    }
    struct Section: Equatable {
        let title: String
        let firstPage: Int
        let lastPage: Int
        let numbering: Int
    }
    struct Link: Equatable {
        enum Kind: Int { case goTo = 2, caption = 3 }
        let bounds: Rect
        let kind: Kind
        let openCheck: Bool
        let destination: Int
        let destinationRect: Rect
    }
    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let detail): return "Invalid CD user guide: \(detail)" }
        }
    }

    let pageIDs: [Int]
    let sections: [Section]
    let pictures: [Int: Data]
    let links: [Int: [Link]]

    init(fork: MacResourceFork) throws {
        var identities = Set<GameDataSourceCatalog.ResourceIdentity>()
        for resource in fork.resources where ["PMAP", "SCNM", "STR#", "RECT", "PICT"].contains(resource.type) {
            guard identities.insert(.init(type: resource.type, id: resource.id)).inserted else {
                throw Failure.invalid("duplicate \(resource.type) \(resource.id)")
            }
        }
        func resource(_ type: String, _ id: Int, maximum: Int) throws -> Data {
            guard let resource = fork[type, id], !resource.isCompressed,
                  !resource.data.isEmpty, resource.data.count <= maximum else {
                throw Failure.invalid("missing, compressed or excessive \(type) \(id)")
            }
            return resource.data
        }
        func rectangle(_ reader: BinaryReader, _ offset: Int) throws -> Rect {
            let rect = try Rect(top: Int(reader.i16(offset)), left: Int(reader.i16(offset + 2)),
                bottom: Int(reader.i16(offset + 4)), right: Int(reader.i16(offset + 6)))
            guard rect.top < rect.bottom, rect.left < rect.right else {
                throw Failure.invalid("empty or reversed rectangle")
            }
            return rect
        }

        let map = try BinaryReader(resource("PMAP", 128, maximum: 2 + 256 * 4))
        let pageCount = Int(try map.u16(0)) + 1
        guard pageCount <= 256, map.count == 2 + pageCount * 4 else {
            throw Failure.invalid("page map count or length")
        }
        var pages: [Int] = []
        for index in 0..<pageCount {
            let id = Int(try map.i32(2 + index * 4))
            guard (1...32767).contains(id), !pages.contains(id) else {
                throw Failure.invalid("duplicate or invalid page ID")
            }
            pages.append(id)
        }

        let sectionData = try BinaryReader(resource("SCNM", 128, maximum: 2 + 256 * 6))
        let sectionCount = Int(try sectionData.u16(0)) + 1
        guard sectionCount <= pageCount, sectionData.count == 2 + sectionCount * 6 else {
            throw Failure.invalid("section count or length")
        }
        let titles = try BinaryReader(resource("STR#", 128, maximum: 2 + 256 * 256))
        guard Int(try titles.u16(0)) == sectionCount else { throw Failure.invalid("section title count") }
        var sections: [Section] = [], titleOffset = 2, nextPage = 1
        for index in 0..<sectionCount {
            let offset = 2 + index * 6
            let first = Int(try sectionData.i16(offset)), last = Int(try sectionData.i16(offset + 2))
            let numbering = Int(try sectionData.i16(offset + 4))
            let title = try titles.pascalString(titleOffset)
            guard first == nextPage, last >= first, last <= pageCount,
                  [-128, 0, 1, 2].contains(numbering), !title.text.isEmpty else {
                throw Failure.invalid("section range, numbering or title")
            }
            sections.append(Section(title: title.text, firstPage: first, lastPage: last, numbering: numbering))
            titleOffset += title.length
            nextPage = last + 1
        }
        guard nextPage == pageCount + 1, titleOffset == titles.count else {
            throw Failure.invalid("incomplete section coverage or trailing title bytes")
        }

        let pageSet = Set(pages)
        var neededPictures = pageSet, links: [Int: [Link]] = [:]
        for page in pages {
            let reader = try BinaryReader(resource("RECT", page, maximum: 2 + 4096 * 24))
            let count = Int(try reader.u16(0))
            guard count <= 4096, reader.count == 2 + count * 24 else {
                throw Failure.invalid("link count or length for page \(page)")
            }
            var pageLinks: [Link] = []
            for index in 0..<count {
                let offset = 2 + index * 24
                let bounds = try rectangle(reader, offset)
                guard let kind = Link.Kind(rawValue: Int(try reader.i16(offset + 8))) else {
                    throw Failure.invalid("unsupported link kind")
                }
                let flag = try reader.u8(offset + 10) // +11 is alignment padding.
                let destination = Int(try reader.i32(offset + 12))
                guard flag <= 1, (1...32767).contains(destination),
                      kind != .goTo || pageSet.contains(destination) else {
                    throw Failure.invalid("link flag or destination")
                }
                let target = try rectangle(reader, offset + 16)
                pageLinks.append(Link(bounds: bounds, kind: kind, openCheck: flag != 0,
                    destination: destination, destinationRect: target))
                neededPictures.insert(destination)
            }
            links[page] = pageLinks
        }
        var pictures: [Int: Data] = [:], total = 0
        for id in neededPictures.sorted() {
            let data = try resource("PICT", id, maximum: 4 * 1024 * 1024)
            total += data.count
            guard total <= 64 * 1024 * 1024, data.count >= 16,
                  Array(data.dropFirst(10).prefix(4)) == [0, 0x11, 2, 0xff] else {
                throw Failure.invalid("picture size or version")
            }
            // Full opcode validation belongs to CDGuidePicture. Check its outer
            // bounds here without copying a multi-megabyte picture into a reader.
            _ = try rectangle(BinaryReader(Data(data.prefix(10))), 2)
            pictures[id] = data
        }
        self.pageIDs = pages
        self.sections = sections
        self.pictures = pictures
        self.links = links
    }
}
