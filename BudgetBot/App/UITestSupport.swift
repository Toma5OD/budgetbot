import Foundation

/// Reads launch arguments to put the app into a deterministic state for
/// XCUITests. Production builds never set these arguments, so behaviour is
/// unchanged.
enum UITestSupport {

    /// When `--ui-test-mode` is set, the auth + key gates are bypassed and the
    /// app boots straight into the main UI with seed data.
    static var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-mode")
    }

    /// When `--ui-test-reset` is set, the on-disk SwiftData store and all
    /// pending shares are wiped on launch.
    static var shouldResetState: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-reset")
    }
}
