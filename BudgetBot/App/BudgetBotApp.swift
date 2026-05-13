import SwiftUI
import SwiftData

@main
struct BudgetBotApp: App {
    @State private var auth = AuthService()
    @State private var fx: FXService
    @State private var theme = ThemeManager()

    init() {
        if UITestSupport.shouldResetState {
            PersistenceController.wipeOnDiskStore()
            PendingCaptureStore.clearAll()
        }
        _fx = State(initialValue: FXService(container: PersistenceController.live))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(fx)
                .environment(theme)
                .tint(theme.current.tint)
                .task {
                    auth.bootstrap()
                    await fx.refreshIfStale()
                }
        }
        .modelContainer(PersistenceController.live)
    }
}
