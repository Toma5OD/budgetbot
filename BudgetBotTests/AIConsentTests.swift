import XCTest
@testable import BudgetBot

final class AIConsentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AIConsent.defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AIConsent.defaultsKey)
        super.tearDown()
    }

    func test_defaultsToNotGranted() {
        // 5.1.2(i): consent must be opt-in — never assumed.
        XCTAssertFalse(AIConsent.isGranted)
        XCTAssertNil(AIConsent.grantedAt)
    }

    func test_grantRecordsTimestamp() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        AIConsent.grant(now: when)
        XCTAssertTrue(AIConsent.isGranted)
        XCTAssertEqual(AIConsent.grantedAt, when)
    }

    func test_revokeClearsGrant() {
        AIConsent.grant()
        AIConsent.revoke()
        XCTAssertFalse(AIConsent.isGranted)
        XCTAssertNil(AIConsent.grantedAt)
    }
}
