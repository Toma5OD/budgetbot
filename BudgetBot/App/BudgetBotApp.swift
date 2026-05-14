import SwiftUI
import SwiftData

@main
struct BudgetBotApp: App {
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
        }
        .modelContainer(PersistenceController.live)
    }
}
