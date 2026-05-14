import XCTest
@testable import BudgetBot

@MainActor
final class BankSyncProviderTests: XCTestCase {

    func test_stubProvider_isNotConfigured() {
        let p = StubBankSyncProvider(name: "Tink", country: "IE")
        XCTAssertFalse(p.isConfigured)
        XCTAssertEqual(p.displayName, "Tink")
        XCTAssertEqual(p.country, "IE")
    }

    func test_stubProvider_throwsNotConfiguredOnConnect() async {
        let p = StubBankSyncProvider(name: "Tink", country: "IE")
        let inst = BankInstitution(id: "x", displayName: "Any Bank", country: "IE")
        do {
            _ = try await p.connect(institution: inst)
            XCTFail("Stub provider must throw on connect")
        } catch let err as BankSyncError {
            switch err {
            case .notConfigured(let provider):
                XCTAssertEqual(provider, "Tink")
            default:
                XCTFail("Expected .notConfigured, got \(err)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_stubProvider_throwsOnInstitutionsAndTransactions() async {
        let p = StubBankSyncProvider(name: "TrueLayer", country: "GB")
        await assertThrowsNotConfigured {
            _ = try await p.availableInstitutions(country: "GB")
        }
        await assertThrowsNotConfigured {
            _ = try await p.transactions(account: "acct-1", since: nil)
        }
    }

    func test_stubProvider_returnsEmptyConnections() async throws {
        let p = StubBankSyncProvider(name: "Plaid", country: "US")
        let conns = try await p.connections()
        XCTAssertTrue(conns.isEmpty)
    }

    func test_stubProvider_disconnectIsIdempotent() async throws {
        let p = StubBankSyncProvider(name: "Plaid", country: "US")
        // Both calls succeed silently.
        try await p.disconnect("anything")
        try await p.disconnect("anything")
    }

    func test_registry_defaultsToFirstProvider() {
        UserDefaults.standard.removeObject(forKey: "BudgetBot.bankProvider")
        XCTAssertEqual(BankSyncRegistry.active.displayName,
                       BankSyncRegistry.all.first?.displayName)
    }

    func test_registry_persistsActiveSelection() {
        BankSyncRegistry.setActive("TrueLayer")
        XCTAssertEqual(BankSyncRegistry.active.displayName, "TrueLayer")
        BankSyncRegistry.setActive("Tink")
        XCTAssertEqual(BankSyncRegistry.active.displayName, "Tink")
        UserDefaults.standard.removeObject(forKey: "BudgetBot.bankProvider")
    }

    // MARK: - Helpers

    private func assertThrowsNotConfigured(
        file: StaticString = #filePath, line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Expected throw", file: file, line: line)
        } catch let err as BankSyncError {
            if case .notConfigured = err {} else {
                XCTFail("Expected .notConfigured got \(err)", file: file, line: line)
            }
        } catch {
            XCTFail("Wrong error type: \(error)", file: file, line: line)
        }
    }
}
