import SwiftUI

struct MainTabView: View {
    @State private var pendingCount: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
                .badge(pendingCount > 0 ? pendingCount : 0)
                .accessibilityIdentifier("tab.capture")

            TransactionListView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                .accessibilityIdentifier("tab.activity")

            AskView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .accessibilityIdentifier("tab.ask")

            AccountsView()
                .tabItem { Label("Accounts", systemImage: "wallet.pass") }
                .accessibilityIdentifier("tab.accounts")

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.pie.fill") }
                .accessibilityIdentifier("tab.analytics")
        }
        .onAppear { refreshPending() }
        .onChange(of: scenePhase) { _, new in
            if new == .active { refreshPending() }
        }
    }

    private func refreshPending() {
        pendingCount = PendingCaptureStore.pending().count
    }
}
