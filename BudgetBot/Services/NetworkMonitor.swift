import Foundation
import Network

/// App-wide connectivity signal, backed by `NWPathMonitor`.
///
/// Two consumers:
///   - **UI** observes `isOnline` to show honest "you're offline"
///     affordances instead of spinners that never resolve.
///   - **CaptureQueueService** registers an `onReconnect` handler so
///     receipts captured offline are processed automatically the
///     moment connectivity returns — the user never has to come back
///     and tap "retry".
///
/// The whole app is local-first (SwiftData on-device, FX rates cached
/// to disk, OCR on-device), so connectivity only gates the genuinely
/// remote flows: AI extraction, the Ask tab, bank sync, and CloudKit
/// mirroring. This monitor exists to make those degrade gracefully
/// rather than fail loudly.
@Observable
@MainActor
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    /// `true` when there's a usable network path. Starts optimistic so
    /// the first render before the initial path callback doesn't flash
    /// an offline state at users who are, in fact, online (the
    /// overwhelming majority, the overwhelming majority of the time).
    private(set) var isOnline: Bool = true

    /// `true` on metered / Low Data Mode paths (cellular, hotspot).
    /// Surfaced now so future features (e.g. bank back-fills) can choose
    /// to wait for Wi-Fi; nothing depends on it yet.
    private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.toma5od.BudgetBot.network",
                                      qos: .utility)
    private var reconnectHandlers: [() -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // pathUpdateHandler fires on `queue`; hop to the main actor
            // before touching observable state.
            Task { @MainActor in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                let cameBackOnline = nowOnline && !self.isOnline
                self.isOnline = nowOnline
                self.isConstrained = path.isConstrained || path.isExpensive
                if cameBackOnline {
                    self.reconnectHandlers.forEach { $0() }
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Register a closure to run when connectivity is *restored* after a
    /// drop (not on the initial satisfied state). Handlers are retained
    /// for the app's lifetime — register from long-lived services only.
    func onReconnect(_ handler: @escaping () -> Void) {
        reconnectHandlers.append(handler)
    }
}
