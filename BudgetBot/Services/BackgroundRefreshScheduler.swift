import Foundation
import BackgroundTasks
import SwiftData

/// Wires `BGTaskScheduler` so iOS can opportunistically wake the app
/// in the background to pull bank transactions while the user isn't
/// looking. The actual sync runs through `BankSyncService` — same code
/// path the foreground "Sync now" button uses, so the two can't drift.
///
/// Lifecycle:
///   - App launch: `register()` registers the task identifier with
///     `BGTaskScheduler` so iOS knows we'd like to run it.
///   - App backgrounded: `scheduleNext()` asks iOS to fire the task
///     "at earliest convenient time" no sooner than 8 hours from now.
///   - iOS fires `handle(task:)`: we run a sync, post-schedule the
///     next one, mark the task complete. iOS gives us ~30 seconds.
///
/// iOS makes no guarantees about *when* the task runs. Some users
/// will see daily refreshes; some will see weekly. That's fine — the
/// manual "Sync now" button is always there.
enum BackgroundRefreshScheduler {

    /// Identifier must also appear in Info.plist under
    /// `BGTaskSchedulerPermittedIdentifiers` — see project.yml.
    static let taskIdentifier = "dev.toma5od.BudgetBot.refresh"

    private static let minimumEarliestBegin: TimeInterval = 8 * 60 * 60   // 8h

    /// Call once at app launch (before `application(_:didFinishLaunching:)`
    /// returns — i.e. from `BudgetBotApp.init` or a `.task` at the root).
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let appRefresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { await handle(task: appRefresh) }
        }
    }

    /// Ask iOS to fire the refresh task in the future. Call this on
    /// `scenePhase` → `.background` so each backgrounding bumps the
    /// timer forward.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(minimumEarliestBegin)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler will throw `.unavailable` on simulator
            // and on devices where Background App Refresh is disabled
            // in Settings — both expected, both non-fatal.
            #if DEBUG
            print("⚠️ BackgroundRefresh schedule failed: \(error)")
            #endif
        }
    }

    /// Cancels any pending request. Useful when the user signs out or
    /// removes the only bank connection.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - Task handler

    @MainActor
    private static func handle(task: BGAppRefreshTask) async {
        // Always schedule the next one first — iOS suspends us if we
        // forget and the chain dies.
        scheduleNext()

        // We get ~30 seconds wall-clock. If the user has lots of
        // connected accounts, a single tx pull may take longer than
        // that and iOS will guillotine us. We cooperate by listening
        // for the expiration handler.
        let work = Task {
            let context = ModelContext(PersistenceController.live)
            _ = await BankSyncService.syncAllConnections(in: context)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
        _ = await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }
}
