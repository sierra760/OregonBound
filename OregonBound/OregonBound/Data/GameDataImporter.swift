import Foundation
import CryptoKit
import OSLog

private let importLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "Import")

/// Turns the player's original files into the decoded data folder the game
/// reads. Sources are identified by their resource contents, not file names,
/// so disk images, MacBinary archives, raw forks and folders all work.
enum GameDataImporter {
    enum Failure: Error, CustomStringConvertible {
        case nothingFound([URL])
        case missing(trail: Bool, color: Bool, found: [String])
        case cancelled
        var description: String {
            switch self {
            case .nothingFound(let urls):
                return "No Macintosh resource forks were found in: " + urls.map(\.lastPathComponent).joined(separator: ", ")
                    + ". Supply the original “Oregon Trail” folder, an HFS or Disk Copy 4.2 disk image, MacBinary (.bin), BinHex (.hqx), AppleDouble, or raw resource-fork (.rsrc) files. StuffIt (.sit) archives must be expanded first."
            case .missing(let trail, let color, let found):
                var needed: [String] = []
                if trail { needed.append("the “Oregon Trail” application (version 1.1)") }
                if color { needed.append("the “Oregon Color” graphics file") }
                let list = found.isEmpty ? "nothing recognizable" : found.joined(separator: ", ")
                return "Still missing \(needed.joined(separator: " and ")). Found: \(list)."
            case .cancelled:
                return "Import cancelled."
            }
        }
    }

    struct Candidate {
        let source: MacForkSource
        let fork: MacResourceFork
        let sha256: String
    }

    struct Classified {
        var trail: Candidate?
        var color: Candidate?
        var system: Candidate?
        var notes: [String] = []
    }

    struct Report {
        let root: URL
        let manifest: GameData.ImportManifest
        let notes: [String]
    }

    /// Classify every fork found under the given URLs.
    static func classify(_ urls: [URL], progress: (String) -> Void) throws -> Classified {
        var candidates: [Candidate] = []
        for url in urls {
            progress("Reading \(url.lastPathComponent)…")
            let sources = try MacContainers.forkSources(at: url)
            for source in sources {
                guard let fork = try? MacResourceFork(data: source.resourceFork), !fork.resources.isEmpty else { continue }
                let digest = SHA256.hash(data: source.resourceFork).map { String(format: "%02x", $0) }.joined()
                candidates.append(Candidate(source: source, fork: fork, sha256: digest))
            }
        }
        guard !candidates.isEmpty else { throw Failure.nothingFound(urls) }
        var classified = Classified()
        func pick(_ role: String, _ preferredName: String, _ matches: (MacResourceFork) -> Bool) -> Candidate? {
            let matching = candidates.filter { matches($0.fork) }
            guard !matching.isEmpty else { return nil }
            let preferred = matching.first { $0.source.displayName.caseInsensitiveCompare(preferredName) == .orderedSame } ?? matching[0]
            if matching.count > 1 {
                classified.notes.append("\(matching.count) candidates for \(role); using \(preferred.source.origin).")
            }
            return preferred
        }
        classified.trail = pick("Oregon Trail", "Oregon Trail") { fork in
            ["DITL", "STR#", "WST#", "snd ", "NFNT", "HVof"].allSatisfy(fork.contains)
        }
        classified.color = pick("Oregon Color", "Oregon Color") { fork in fork.contains("Imag") && fork.contains("cicn") }
        classified.system = pick("System", "System") { fork in
            fork["CDEF", 1] != nil && fork["FOND", 0] != nil && fork["FOND", 3] != nil && fork["ICON", 0] != nil
        }
        return classified
    }

    static func run(sources urls: [URL], destination: URL = GameData.storageDirectory,
                    progress: @escaping (String) -> Void, isCancelled: () -> Bool = { false }) throws -> Report {
        let classified = try classify(urls, progress: progress)
        guard let trail = classified.trail, let color = classified.color else {
            let found = [classified.trail, classified.color, classified.system].compactMap { $0?.source.origin }
            throw Failure.missing(trail: classified.trail == nil, color: classified.color == nil, found: found)
        }
        var notes = classified.notes
        let staging = destination.deletingLastPathComponent().appendingPathComponent("GameData.importing", isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let output = ExtractionOutput(root: staging)
        func step(_ message: String, _ work: () throws -> Void) throws {
            if isCancelled() { throw Failure.cancelled }
            progress(message)
            importLogger.info("\(message, privacy: .public)")
            try work()
        }
        try step("Decoding graphics…") { _ = try GraphicsExtractor.extract(colorFork: color.fork, into: output) }
        try step("Decoding introduction pictures…") { try GraphicsExtractor.extractTextPictures(trailFork: trail.fork, into: output) }
        try step("Decoding fonts…") { _ = try BitmapFontExtractor.extractGameFonts(trailFork: trail.fork, into: output, sourceSHA256: trail.sha256) }
        try step("Decoding sounds…") { _ = try SoundExtractor.extractSounds(trailFork: trail.fork, into: output) }
        try step("Decoding text, dialogs and map data…") { try TextResourceExtractors.extractAll(trailFork: trail.fork, into: output) }
        try step("Importing animation and cursor resources…") {
            try RuntimeResourceExtractor.extract(trailFork: trail.fork, into: output)
        }
        var hasSystem = false
        if let system = classified.system {
            try step("Decoding System 7.0 fonts…") { _ = try BitmapFontExtractor.extractSystemFonts(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256) }
            try step("Decoding System 7.0 controls…") { try SystemControlsExtractor.extractAll(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256) }
            hasSystem = true
        } else {
            notes.append("No System 7.0 System file was supplied: Chicago and Geneva text, alert icons and scroll bars will use fallbacks.")
        }
        var sources = [trail, color].map { GameData.ImportManifest.Source(role: $0 === trail ? "Oregon Trail" : "Oregon Color",
                                                                             origin: $0.source.origin, sha256: $0.sha256,
                                                                             length: $0.source.resourceFork.count) }
        if let system = classified.system {
            sources.append(.init(role: "System", origin: system.source.origin, sha256: system.sha256, length: system.source.resourceFork.count))
        }
        let manifest = GameData.ImportManifest(layoutVersion: GameData.layoutVersion, importedAt: Date(),
                                               sources: sources, hasSystemResources: hasSystem)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try output.write(try encoder.encode(manifest), to: GameData.manifestName)
        try step("Installing…") {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: staging, to: destination)
        }
        return Report(root: destination, manifest: manifest, notes: notes)
    }
}

private func === (lhs: GameDataImporter.Candidate, rhs: GameDataImporter.Candidate) -> Bool { lhs.sha256 == rhs.sha256 }

/// `"Oregon Bound" --import <file-or-folder>... [--output <folder>]` decodes the
/// data without launching the game, for scripted verification.
enum GameDataCommandLine {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard let start = arguments.firstIndex(of: "--import") else { return nil }
        var sources: [URL] = []
        var output = GameData.storageDirectory
        var index = start + 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--output", index + 1 < arguments.count {
                output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true); index += 2; continue
            }
            sources.append(URL(fileURLWithPath: argument)); index += 1
        }
        guard !sources.isEmpty else { print("usage: \"Oregon Bound\" --import <file-or-folder>... [--output <folder>]"); return 2 }
        do {
            let report = try GameDataImporter.run(sources: sources, destination: output) { print($0) }
            for source in report.manifest.sources { print("\(source.role): \(source.origin) sha256=\(source.sha256)") }
            report.notes.forEach { print("note: \($0)") }
            print("Imported into \(report.root.path)")
            return 0
        } catch {
            print("error: \(error)")
            return 1
        }
    }
}
