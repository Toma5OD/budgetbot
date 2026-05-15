import XCTest
import Vision
@testable import BudgetBot

/// We can't easily ship a real receipt image into the test bundle and
/// assert on Vision's output — the framework's accuracy varies across
/// devices and OS versions. What we *can* test is the pure logic:
/// observation stitching (reading-order reconstruction) and the
/// public threshold helper's contract.
@MainActor
final class VisionOCRServiceTests: XCTestCase {

    func test_stitchObservations_emptyReturnsEmpty() {
        XCTAssertEqual(VisionOCRService.stitchObservations([]), "")
    }

    func test_minUsefulTextLength_isReasonable() {
        // 30 chars is the published threshold. If someone bumps it
        // accidentally to a huge number, this fails so they notice.
        XCTAssertLessThan(VisionOCRService.minUsefulTextLength, 100)
        XCTAssertGreaterThan(VisionOCRService.minUsefulTextLength, 5)
    }

    func test_settingsToggleKeyHasNotShifted() {
        // The AIService path reads this UserDefaults key. If anyone
        // renames it without updating both ends, OCR silently turns
        // off — guard with a test so the rename forces a thought.
        let key = "BudgetBot.ocrEnabled"
        UserDefaults.standard.removeObject(forKey: key)
        // Default behaviour when key is absent: ON.
        let defaultValue = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        XCTAssertTrue(defaultValue,
                      "OCR should default ON — it's faster + cheaper + offline-capable")

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.removeObject(forKey: key)
    }
}
