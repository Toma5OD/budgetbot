import Foundation
import SwiftData

/// Single sync orchestrator that both manual "Sync now" taps and the
/// background refresh task funnel through. Sits between the
/// `BankSyncProvider` (raw API) and the `BankTransactionImporter`
/// (raw → SwiftData) so the two callers don't drift apart.
@MainActor
enum BankSyncService {

    struct Summary: Equatable {
        var inserted: Int = 0
        var updated: Int = 0
        var skippedDuplicate: Int = 0
        var accountsTouched: Int = 0
        var errors: [String] = []
    }

    /// Pulls transactions for every connected account on the active
    /// provider. Creates / reuses a local `Account` per bank account so
    /// the Transactions land somewhere sensible.
    @discardableResult
    static func syncAllConnections(in context: ModelContext) async -> Summary {
        var summary = Summary()
        let provider = BankSyncRegistry.active
        guard provider.isConfigured else { return summary }

        let connections: [BankConnection]
        do {
            connections = try await provider.connections()
        } catch {
            summary.errors.append("List connections: \(error.localizedDescription)")
            return summary
        }

        for connection in connections {
            for acct in connection.accounts {
                summary.accountsTouched += 1
                do {
                    let local = ensureLocalAccount(
                        for: acct,
                        institution: connection.institution,
                        context: context
                    )
                    let (rows, _) = try await provider.transactions(
                        account: acct.id, since: nil
                    )
                    let r = try BankTransactionImporter.importRows(
                        rows, into: local, context: context
                    )
                    summary.inserted += r.inserted
                    summary.updated += r.updated
                    summary.skippedDuplicate += r.skippedDuplicate
                } catch {
                    summary.errors.append("\(acct.displayName): \(error.localizedDescription)")
                }
            }
        }
        return summary
    }

    /// Single-account sync — used by the per-card "Sync now" button.
    @discardableResult
    static func syncConnection(
        _ connection: BankConnection,
        in context: ModelContext
    ) async -> Summary {
        var summary = Summary()
        let provider = BankSyncRegistry.active
        guard provider.isConfigured else { return summary }

        for acct in connection.accounts {
            summary.accountsTouched += 1
            do {
                let local = ensureLocalAccount(
                    for: acct,
                    institution: connection.institution,
                    context: context
                )
                let (rows, _) = try await provider.transactions(
                    account: acct.id, since: nil
                )
                let r = try BankTransactionImporter.importRows(
                    rows, into: local, context: context
                )
                summary.inserted += r.inserted
                summary.updated += r.updated
                summary.skippedDuplicate += r.skippedDuplicate
            } catch {
                summary.errors.append("\(acct.displayName): \(error.localizedDescription)")
            }
        }
        return summary
    }

    // MARK: - Helpers

    /// Find-or-create the local `Account` row that mirrors this bank
    /// account. Matches on the conventional naming so re-connect /
    /// re-sync don't fork into duplicates.
    private static func ensureLocalAccount(
        for acct: BankAccountInfo,
        institution: BankInstitution,
        context: ModelContext
    ) -> Account {
        let candidates = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let name = "\(institution.displayName) — \(acct.displayName)"
        if let match = candidates.first(where: { $0.name == name }) {
            return match
        }
        let kind: AccountKind = {
            switch acct.kindRaw.lowercased() {
            case "credit", "credit_card", "creditcard": return .credit
            case "savings":                              return .savings
            case "cash":                                 return .cash
            default:                                     return .bank
            }
        }()
        let local = Account(
            name: name,
            kind: kind,
            institution: institution.displayName,
            currency: acct.currency,
            openingBalance: acct.balance ?? 0
        )
        context.insert(local)
        return local
    }
}
