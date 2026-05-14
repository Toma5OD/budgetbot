import XCTest
@testable import BudgetBot

@MainActor
final class LocalNotificationServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Wipe persisted preferences between tests so each starts clean.
        for key in [
            "BudgetBot.notif.enabled",
            "BudgetBot.notif.weeklyRecap",
            "BudgetBot.notif.subscriptionRenewal",
            "BudgetBot.notif.budgetThreshold"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Wipe month-tagged dedup keys for the current month.
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        let tag = df.string(from: .now)
        UserDefaults.standard.removeObject(forKey: "BudgetBot.notif.budgetCrossed75.\(tag)")
        UserDefaults.standard.removeObject(forKey: "BudgetBot.notif.budgetCrossed100.\(tag)")
    }

    func test_defaultPrefs_masterOffSubrequestsOn() {
        let s = LocalNotificationService.shared
        // Master toggle defaults to off — the user must opt in.
        XCTAssertFalse(s.enabled)
        // Sub-toggles default to on so flipping the master once "just
        // works" — no surprise empty notifications.
        XCTAssertTrue(s.weeklyRecapEnabled)
        XCTAssertTrue(s.subscriptionRenewalEnabled)
        XCTAssertTrue(s.budgetThresholdEnabled)
    }

    func test_disablingMaster_persistsAcrossReads() {
        let s = LocalNotificationService.shared
        s.enabled = true
        XCTAssertTrue(s.enabled)
        s.enabled = false
        XCTAssertFalse(s.enabled)
    }

    func test_budgetThresholdDedup_doesNotDoubleFire() {
        let s = LocalNotificationService.shared
        s.enabled = true
        s.budgetThresholdEnabled = true

        // Cross 75% — sets the dedup key.
        s.budgetSpendChanged(spent: 80, budget: 100, currency: "EUR")
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        let tag = df.string(from: .now)
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: "BudgetBot.notif.budgetCrossed75.\(tag)"),
            "Crossing 75% should set the dedup key for this month")

        // Same threshold again — dedup key already set, no re-trigger.
        s.budgetSpendChanged(spent: 90, budget: 100, currency: "EUR")
        // No good way to assert "no new notification scheduled" without
        // talking to UNUserNotificationCenter, but the dedup key
        // remaining true (rather than being reset) is the contract.
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: "BudgetBot.notif.budgetCrossed75.\(tag)"))
    }

    func test_budgetThreshold_ignoredWhenMasterOff() {
        let s = LocalNotificationService.shared
        s.enabled = false
        s.budgetThresholdEnabled = true
        s.budgetSpendChanged(spent: 200, budget: 100, currency: "EUR")
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        let tag = df.string(from: .now)
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: "BudgetBot.notif.budgetCrossed100.\(tag)"),
            "Master toggle off must short-circuit before fireOnce()")
    }

    func test_welcomeFlag_persists() {
        WelcomeFlow.hasCompletedWelcome = false
        XCTAssertFalse(WelcomeFlow.hasCompletedWelcome)
        WelcomeFlow.hasCompletedWelcome = true
        XCTAssertTrue(WelcomeFlow.hasCompletedWelcome)
        WelcomeFlow.hasCompletedWelcome = false
    }
}
