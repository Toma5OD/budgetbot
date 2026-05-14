import SwiftUI
import SwiftData

@main
struct BudgetBotApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthService()
    @State private var fx: FXService
    @State private var theme = ThemeManager()
    @State private var notifs = NotificationStore()
    @State private var queue: CaptureQueueService

    init() {
        if UITestSupport.shouldResetState {
            PersistenceController.wipeOnDiskStore()
            PendingCaptureStore.clearAll()
        }
        let fxService = FXService(container: PersistenceController.live)
        let q = CaptureQueueService(container: PersistenceController.live)
        q.wire(fx: fxService)
        _fx = State(initialValue: fxService)
        _queue = State(initialValue: q)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(fx)
                .environment(theme)
                .environment(notifs)
                .environment(queue)
                .tint(theme.current.tint)
                .preferredColorScheme(theme.current.preferredScheme)
                .themedBackground(theme.current)
                .task {
                    auth.bootstrap()
                    await fx.refreshIfStale()
                    queue.pump()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Refresh the widget data + reschedule local
                        // notifications whenever the app comes to the
                        // foreground. Cheap; writes are atomic and
                        // UNUserNotificationCenter coalesces.
                        let context = ModelContext(PersistenceController.live)
                        WidgetSnapshotService.refresh(context: context, fx: fx)
                        Task { await rescheduleLocalNotifications(context: context) }
                    }
                }
        }
        .modelContainer(PersistenceController.live)
    }

    @MainActor
    private func rescheduleLocalNotifications(context: ModelContext) async {
        let rules = (try? context.fetch(
            FetchDescriptor<RecurringRule>(predicate: #Predicate { !$0.dismissed })
        )) ?? []
        // Translate the SwiftData rules into the service's plain-struct
        // input, projecting the next expected fire date from cadence +
        // lastSeen. Rough but adequate for a T-1 reminder.
        let inputs: [LocalNotificationService.SubscriptionReminderInput] = rules.compactMap { r in
            guard let next = nextExpected(rule: r) else { return nil }
            return .init(
                id: r.id, displayName: r.displayName,
                monthlyEstimate: r.monthlyEstimate,
                currency: r.currency,
                nextExpectedDate: next
            )
        }
        await LocalNotificationService.shared.reschedule(subscriptions: inputs)
    }

    private func nextExpected(rule: RecurringRule) -> Date? {
        let cal = Calendar.current
        let stride: DateComponents
        switch rule.cadence {
        case .weekly:  stride = DateComponents(day: 7)
        case .monthly: stride = DateComponents(month: 1)
        case .yearly:  stride = DateComponents(year: 1)
        }
        return cal.date(byAdding: stride, to: rule.lastSeen)
    }
}
