import Foundation

/// Prepares an import beside its destination, then installs with rollback.
/// Every attempt owns its temporary paths; another import's staging is untouched.
enum GameDataInstallation {
    enum Failure: Error, CustomStringConvertible {
        case cancelled
        case notDirectory(URL)
        case rollback(backup: URL, installation: Error, restoration: Error)
        var description: String {
            switch self {
            case .cancelled: return "Import cancelled."
            case .notDirectory(let url): return "The import destination is not a directory: \(url.path)"
            case .rollback(let backup, let installation, let restoration):
                return "Installation failed (\(installation)); the previous import could not be restored (\(restoration)). Your previous data is preserved at \(backup.path)."
            }
        }
    }

    private static let installationLock = NSLock()

    static func run<Result>(destination: URL, isCancelled: () -> Bool = { false },
                            move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
                            prepare: (URL) throws -> Result) throws -> Result {
        if isCancelled() { throw Failure.cancelled }
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let token = UUID().uuidString
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).importing-\(token)", isDirectory: true)
        let backup = parent.appendingPathComponent(".\(destination.lastPathComponent).backup-\(token)", isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let result = try prepare(staging)

        // Preparation can overlap; directory replacement in this process cannot.
        installationLock.lock()
        defer { installationLock.unlock() }
        if isCancelled() { throw Failure.cancelled }
        var isDirectory: ObjCBool = false
        let hadPrevious = manager.fileExists(atPath: destination.path, isDirectory: &isDirectory)
        if hadPrevious && !isDirectory.boolValue { throw Failure.notDirectory(destination) }
        if hadPrevious { try move(destination, backup) }
        do {
            try move(staging, destination)
        } catch {
            let installationError = error
            if hadPrevious {
                do { try move(backup, destination) }
                catch { throw Failure.rollback(backup: backup, installation: installationError, restoration: error) }
            }
            throw installationError
        }
        // Installation succeeded. A cleanup failure may leave an old backup but
        // must not turn a completed install into a reported import failure.
        if hadPrevious { try? manager.removeItem(at: backup) }
        return result
    }
}
