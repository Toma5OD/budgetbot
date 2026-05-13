import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var pendingCount: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
                .accessibilityIdentifier("tab.home")

            TransactionListView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                .tag(1)
                .accessibilityIdentifier("tab.activity")

            CaptureView()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
                .badge(pendingCount > 0 ? pendingCount : 0)
                .tag(2)
                .accessibilityIdentifier("tab.capture")

            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.pie.fill") }
                .tag(3)
                .accessibilityIdentifier("tab.analytics")

            AskView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .tag(4)
                .accessibilityIdentifier("tab.ask")
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
