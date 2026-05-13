import SwiftUI
import SwiftData

/// Attaches the universal header to a NavigationStack-rooted view:
///   leading: profile avatar  -> ProfileView sheet
///   trailing: bell + gear    -> NotificationCenter / Settings sheets
///
/// Apply with `.appHeaderToolbar()` on each primary tab's root view.
struct AppHeaderToolbar: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Environment(NotificationStore.self) private var notifs
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var showProfile = false
    @State private var showNotifications = false
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfile = true
                    } label: {
                        AvatarCircle(initials: initials, size: 32, tint: theme.current.tint)
                    }
                    .accessibilityLabel("Profile")
                    .accessibilityIdentifier("header.profile")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifs.unreadCount > 0 ? "bell.badge.fill" : "bell")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(notifs.unreadCount > 0 ? theme.current.tint : .primary)
                            if notifs.unreadCount > 0 {
                                Text("\(min(notifs.unreadCount, 9))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Color.red, in: Circle())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                    .accessibilityLabel("Notifications")
                    .accessibilityIdentifier("header.notifications")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("header.settings")
                }
            }
            .sheet(isPresented: $showProfile) {
                NavigationStack { ProfileView() }
            }
            .sheet(isPresented: $showNotifications) {
                NavigationStack { NotificationCenterView() }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
    }

    private var initials: String {
        let name = profiles.first?.displayName ?? profiles.first?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : chars.joined()
    }
}

extension View {
    /// Universal app-level header: profile avatar (lead), notifications bell
    /// + settings gear (trail). Use on every primary tab.
    func appHeaderToolbar() -> some View {
        modifier(AppHeaderToolbar())
    }
}
