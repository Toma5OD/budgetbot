import Foundation

/// File-backed queue of attachments shared from the system Share Sheet to the
/// main app. Writes from the ShareExtension process, reads + deletes from the
/// BudgetBot app process. App Group container keeps them visible to both.
///
/// Wire layout:
///
///     <AppGroup>/PendingCaptures/<UUID>.json   ← manifest
///     <AppGroup>/PendingCaptures/<UUID>.bin    ← payload (image/pdf), if any
struct PendingCapture: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case image, pdf, text }

    let id: UUID
    let kind: Kind
    let filename: String?
    let createdAt: Date
    /// Inline text payload (only set for `.text`).
    let text: String?
    /// File name (NOT full path; resolved against the queue dir).
    let binaryFilename: String?
}

enum PendingCaptureStore {

    enum Err: Error { case noContainer, write(String) }

    /// Test seam. Production code never sets this; tests assign a temp
    /// directory so they don't depend on the App Group entitlement (which
    /// requires code signing to resolve in the simulator).
    nonisolated(unsafe) static var queueDirOverride: URL?

    private static func queueDir() throws -> URL {
        if let override = queueDirOverride {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID
        ) else { throw Err.noContainer }
        let dir = base.appendingPathComponent("PendingCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Writes (called from the Share Extension)

    @discardableResult
    static func writeImage(_ data: Data, filename: String?) throws -> PendingCapture {
        try writeBlob(kind: .image, data: data, filename: filename, ext: "jpg")
    }

    @discardableResult
    static func writePDF(_ data: Data, filename: String?) throws -> PendingCapture {
        try writeBlob(kind: .pdf, data: data, filename: filename, ext: "pdf")
    }

    @discardableResult
    static func writeText(_ text: String) throws -> PendingCapture {
        let dir = try queueDir()
        let id = UUID()
        let item = PendingCapture(
            id: id,
            kind: .text,
            filename: nil,
            createdAt: Date(),
            text: text,
            binaryFilename: nil
        )
        let manifestURL = dir.appendingPathComponent("\(id.uuidString).json")
        try JSONEncoder.iso.encode(item).write(to: manifestURL, options: .atomic)
        return item
    }

    private static func writeBlob(kind: PendingCapture.Kind, data: Data, filename: String?, ext: String) throws -> PendingCapture {
        let dir = try queueDir()
        let id = UUID()
        let binName = "\(id.uuidString).\(ext)"
        let binURL = dir.appendingPathComponent(binName)
        do { try data.write(to: binURL, options: .atomic) }
        catch { throw Err.write(error.localizedDescription) }

        let item = PendingCapture(
            id: id,
            kind: kind,
            filename: filename,
            createdAt: Date(),
            text: nil,
            binaryFilename: binName
        )
        let manifestURL = dir.appendingPathComponent("\(id.uuidString).json")
        try JSONEncoder.iso.encode(item).write(to: manifestURL, options: .atomic)
        return item
    }

    // MARK: - Reads (main app)

    static func pending() -> [PendingCapture] {
        guard let dir = try? queueDir(),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder.iso.decode(PendingCapture.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func loadBinary(_ item: PendingCapture) -> Data? {
        guard let bin = item.binaryFilename,
              let dir = try? queueDir() else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(bin))
    }

    static func remove(_ id: UUID) {
        guard let dir = try? queueDir() else { return }
        let manifest = dir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: manifest)
        // Remove any binary that has the UUID prefix.
        if let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for u in urls where u.lastPathComponent.hasPrefix(id.uuidString) {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    static func clearAll() {
        guard let dir = try? queueDir() else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}

// Use `secondsSince1970` so sub-second ordering survives the JSON round-trip;
// the default `.iso8601` strategy only writes whole-second precision and
// breaks `pending()`'s sort order for items created in the same second.
private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
