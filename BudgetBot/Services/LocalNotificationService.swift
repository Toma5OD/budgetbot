import Foundation
import UserNotifications

/// Local-only notification scheduling. No APNs / server — we use
/// `UNUserNotificationCenter` to plant timed notifications and rebuild
/// the schedule whenever the user toggles settings, signs in, or
/// foregrounds the app.
///
/// Three notification types ship in this first cut. Each is gated on its
/// own user preference (UserDefaults) so users can keep some on and turn
/// others off without dropping the master permission.
///
///   - **weeklyRecap** — repeating, Sunday 18:00 local. "Here's your week."
///   - **subscriptionRenewal** — one shot per detected sub, fires T-1 day
///     before the next expected occurrence.
///   - **budgetThreshold** — fired immediately from the app when monthly
///     spend crosses 75% or 100% of the user's budget. Not pre-scheduled.
///
/// Budget-threshold notifications use a deduplication key so they don't
/// re-fire if the user adds another tx after crossing the threshold.
@MainActor
final class LocalNotificationService {

    static let shared = LocalNotificationService()
    private init() {}

    // MARK: - Preferences (UserDefaults)

    private enum Key {
        static let enabled       = "BudgetBot.notif.enabled"
        static let weekly        = "BudgetBot.notif.weeklyRecap"
        static let subscriptions = "BudgetBot.notif.subscriptionRenewal"
        static let budget        = "BudgetBot.notif.budgetThreshold"
        static let crossed75     = "BudgetBot.notif.budgetCrossed75."   // + YYYY-MM
        static let crossed100    = "BudgetBot.notif.budgetCrossed100."  // + YYYY-MM
    }

    /// Master toggle. When `false`, every scheduled request is removed
    /// and nothing new can fire.
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.enabled)
            if !newValue { Task { await cancelAll() } }
        }
    }
    var weeklyRecapEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.weekly) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.weekly) }
    }
    var subscriptionRenewalEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.subscriptions) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.subscriptions) }
    }
    var budgetThresholdEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.budget) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.budget) }
    }

    // MARK: - Permission

    /// Returns the current authorisation status without prompting.
    func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Prompts the user (idempotent — iOS only prompts once; subsequent
    /// calls return the existing decision). Returns whether we ended up
    /// authorized.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Wipes pending requests then rebuilds them from current state.
    /// Called on app foreground, after sign-in, and from any settings
    /// toggle change.
    func reschedule(subscriptions: [SubscriptionReminderInput]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        if weeklyRecapEnabled            { scheduleWeeklyRecap() }
        if subscriptionRenewalEnabled    { schedule(subscriptions: subscriptions) }
        // Budget threshold is event-driven, not pre-scheduled.
    }

    /// Cancel everything (used when the master toggle goes off).
    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Weekly recap

    private func scheduleWeeklyRecap() {
        let content = UNMutableNotificationContent()
        content.title = "How'd the week go?"
        content.body = "Tap to see your weekly recap — spending, top categories, the regrets."
        content.sound = .default
        content.threadIdentifier = "weeklyRecap"

        var dc = DateComponents()
        dc.weekday = 1   // Sunday in Apple's calendar (Sun = 1)
        dc.hour    = 18
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let req = UNNotificationRequest(identifier: "weeklyRecap",
                                        content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Subscription renewals

    /// Lightweight snapshot of a `RecurringRule` so this service doesn't
    /// depend on the SwiftData type directly — keeps it testable.
    struct SubscriptionReminderInput {
        let id: UUID
        let displayName: String
        let monthlyEstimate: Decimal
        let currency: String
        let nextExpectedDate: Date
    }

    private func schedule(subscriptions: [SubscriptionReminderInput]) {
        let cal = Calendar.current
        for sub in subscriptions {
            guard let fireDate = cal.date(byAdding: .day, value: -1,
                                          to: sub.nextExpectedDate),
                  fireDate > .now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(sub.displayName) charges tomorrow"
            content.body = "About \(CurrencyFormatter.string(for: -sub.monthlyEstimate, currency: sub.currency)) — cancel now if it's not pulling its weight."
            content.sound = .default
            content.threadIdentifier = "subscriptionRenewal.\(sub.id.uuidString)"

            let dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let req = UNNotificationRequest(
                identifier: "sub.\(sub.id.uuidString)",
                content: content, trigger: trigger
            )
            UNUserNotificationCenter.current().add(req)
        }
    }

    // MARK: - Budget threshold (event-driven)

    /// Call when monthly spend changes (after a commit). Fires a
    /// one-shot notification the first time the current month crosses
    /// 75% or 100% — dedup keys are scoped to `YYYY-MM` so a fresh month
    /// resets them.
    func budgetSpendChanged(spent: Decimal, budget: Decimal, currency: String,
                            now: Date = .now) {
        guard enabled, budgetThresholdEnabled, budget > 0 else { return }
        let pct = NSDecimalNumber(decimal: spent).doubleValue
            / NSDecimalNumber(decimal: budget).doubleValue
        let monthTag = monthKey(now)

        if pct >= 1.0 {
            fireOnce(key: Key.crossed100 + monthTag,
                     title: "You're over budget.",
                     body: "Spent \(CurrencyFormatter.string(for: spent, currency: currency)) of \(CurrencyFormatter.string(for: budget, currency: currency)) this month.")
        } else if pct >= 0.75 {
            fireOnce(key: Key.crossed75 + monthTag,
                     title: "75% of the budget gone.",
                     body: "\(CurrencyFormatter.string(for: budget - spent, currency: currency)) left for the rest of the month.")
        }
    }

    private func fireOnce(key: String, title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: key) == false else { return }
        UserDefaults.standard.set(true, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: key, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func monthKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        return df.string(from: date)
    }
}
