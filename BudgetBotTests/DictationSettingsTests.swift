import XCTest
@testable import BudgetBot

final class DictationSettingsTests: XCTestCase {

    private let keys = [
        "BudgetBot.dictation.engine",
        "BudgetBot.dictation.language",
        "BudgetBot.dictation.punctuation",
        "BudgetBot.dictation.offlineFallback"
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        KeychainService.shared.delete(.openAIKey)
        KeychainService.shared.delete(.geminiKey)
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        KeychainService.shared.delete(.openAIKey)
        KeychainService.shared.delete(.geminiKey)
        super.tearDown()
    }

    // MARK: - Defaults

    func test_defaults() {
        XCTAssertEqual(DictationSettings.engine, .onDevice)
        XCTAssertNil(DictationSettings.languageCode)
        XCTAssertTrue(DictationSettings.addsPunctuation)
        XCTAssertTrue(DictationSettings.offlineFallback)
    }

    func test_roundTrips() {
        DictationSettings.engine = .whisper
        XCTAssertEqual(DictationSettings.engine, .whisper)
        DictationSettings.languageCode = "en-IE"
        XCTAssertEqual(DictationSettings.languageCode, "en-IE")
        DictationSettings.languageCode = nil
        XCTAssertNil(DictationSettings.languageCode)
        DictationSettings.addsPunctuation = false
        XCTAssertFalse(DictationSettings.addsPunctuation)
    }

    // MARK: - Engine metadata

    func test_engineMetadata() {
        XCTAssertFalse(DictationEngine.onDevice.isCloud)
        XCTAssertTrue(DictationEngine.whisper.isCloud)
        XCTAssertTrue(DictationEngine.gemini.isCloud)
        XCTAssertNil(DictationEngine.onDevice.keychainKey)
        XCTAssertEqual(DictationEngine.whisper.keychainKey, .openAIKey)
        XCTAssertEqual(DictationEngine.gemini.keychainKey, .geminiKey)
    }

    // MARK: - Effective engine

    func test_onDevice_alwaysOnDevice() {
        DictationSettings.engine = .onDevice
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: false), .onDevice)
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: true), .onDevice)
    }

    func test_cloudWithoutKey_fallsBackWhenAllowed() {
        DictationSettings.engine = .whisper
        DictationSettings.offlineFallback = true
        // No key set → fall back to on-device.
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: true), .onDevice)
    }

    func test_cloudWithoutKey_staysCloudWhenFallbackOff() {
        DictationSettings.engine = .whisper
        DictationSettings.offlineFallback = false
        // Stays on the chosen cloud engine (will then surface a missing-key error).
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: true), .whisper)
    }

    func test_cloudWithKey_offline_fallsBack() throws {
        DictationSettings.engine = .whisper
        DictationSettings.offlineFallback = true
        try? KeychainService.shared.set("sk-test", for: .openAIKey)
        // The Keychain isn't writable in the test host (no access group),
        // same as the widget/App-Group tests — skip rather than fail.
        try XCTSkipUnless(KeychainService.shared.get(.openAIKey) == "sk-test",
                          "Keychain unavailable in this test runtime")
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: false), .onDevice)
        XCTAssertEqual(DictationSettings.effectiveEngine(isOnline: true), .whisper)
    }

    // MARK: - Language menu

    func test_languageMenuHasDeviceDefault() {
        XCTAssertEqual(DictationSettings.languageOptions.first?.code, nil)
        XCTAssertTrue(DictationSettings.languageOptions.contains { $0.code == "en-IE" })
    }
}
