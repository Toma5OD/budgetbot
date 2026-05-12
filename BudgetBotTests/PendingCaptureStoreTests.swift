import XCTest
@testable import BudgetBot

/// Uses a temp directory injected via `PendingCaptureStore.queueDirOverride`
/// so the tests don't depend on the App Group entitlement.
final class PendingCaptureStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("budgetbot-tests-\(UUID().uuidString)")
        PendingCaptureStore.queueDirOverride = tempDir
        PendingCaptureStore.clearAll()
    }

    override func tearDown() {
        PendingCaptureStore.clearAll()
        try? FileManager.default.removeItem(at: tempDir)
        PendingCaptureStore.queueDirOverride = nil
        super.tearDown()
    }

    func test_writeText_roundTripsThroughPending() throws {
        let item = try PendingCaptureStore.writeText("Bought a coffee for €3.20")
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.text, "Bought a coffee for €3.20")

        let pending = PendingCaptureStore.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.text, "Bought a coffee for €3.20")
    }

    func test_writeImage_persistsBinary() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])  // tiny fake JPEG header
        let item = try PendingCaptureStore.writeImage(bytes, filename: "scan.jpg")
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.filename, "scan.jpg")

        let loaded = PendingCaptureStore.loadBinary(item)
        XCTAssertEqual(loaded, bytes)
    }

    func test_writePDF_persistsBinary() throws {
        let bytes = Data("%PDF-1.7".utf8) + Data(repeating: 0, count: 32)
        let item = try PendingCaptureStore.writePDF(bytes, filename: "statement.pdf")
        XCTAssertEqual(item.kind, .pdf)
        XCTAssertEqual(item.filename, "statement.pdf")
        XCTAssertEqual(PendingCaptureStore.loadBinary(item), bytes)
    }

    func test_remove_clearsManifestAndBinary() throws {
        let item = try PendingCaptureStore.writeImage(Data([0x00, 0x01]), filename: nil)
        XCTAssertEqual(PendingCaptureStore.pending().count, 1)
        PendingCaptureStore.remove(item.id)
        XCTAssertEqual(PendingCaptureStore.pending().count, 0)
        XCTAssertNil(PendingCaptureStore.loadBinary(item))
    }

    func test_pendingOrderingByCreatedAt() throws {
        let a = try PendingCaptureStore.writeText("first")
        Thread.sleep(forTimeInterval: 0.01)
        let b = try PendingCaptureStore.writeText("second")
        let ids = PendingCaptureStore.pending().map { $0.id }
        XCTAssertEqual(ids, [a.id, b.id])
    }

    func test_clearAll_wipesQueue() throws {
        _ = try PendingCaptureStore.writeText("a")
        _ = try PendingCaptureStore.writeText("b")
        XCTAssertEqual(PendingCaptureStore.pending().count, 2)
        PendingCaptureStore.clearAll()
        XCTAssertEqual(PendingCaptureStore.pending().count, 0)
    }

    func test_mixedKinds_listedTogether() throws {
        _ = try PendingCaptureStore.writeText("note")
        _ = try PendingCaptureStore.writeImage(Data([0x01]), filename: "a.jpg")
        _ = try PendingCaptureStore.writePDF(Data([0x02]), filename: "b.pdf")
        let kinds = PendingCaptureStore.pending().map { $0.kind }
        XCTAssertEqual(Set(kinds), Set([.text, .image, .pdf]))
    }
}
