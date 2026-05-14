import XCTest
@testable import BudgetBot

/// Verifies the Codable wire types match real GoCardless response
/// shapes. Snippets below are abridged from the public API docs at
/// developer.gocardless.com/bank-account-data.
final class GoCardlessWireTests: XCTestCase {

    func test_tokenResponseDecodes() throws {
        let json = """
        {
          "access": "eyJ0eXAi...",
          "access_expires": 86400,
          "refresh": "eyJ0eXAi...",
          "refresh_expires": 2592000
        }
        """
        let t = try JSONDecoder().decode(
            GoCardlessAPI.TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(t.access_expires, 86400)
        XCTAssertEqual(t.refresh_expires, 2592000)
    }

    func test_institutionDecodes() throws {
        let json = """
        {
          "id": "BANK_OF_IRELAND_BOFIIE2D",
          "name": "Bank of Ireland",
          "bic": "BOFIIE2D",
          "transaction_total_days": "90",
          "countries": ["IE"],
          "logo": "https://cdn.gocardless.com/logos/bofi.png"
        }
        """
        let i = try JSONDecoder().decode(
            GoCardlessAPI.Institution.self, from: Data(json.utf8))
        XCTAssertEqual(i.id, "BANK_OF_IRELAND_BOFIIE2D")
        XCTAssertEqual(i.countries?.first, "IE")
    }

    func test_requisitionDecodes() throws {
        let json = """
        {
          "id": "8bbedf14-15bd-4f8b-83b0-66f76dc91d39",
          "created": "2026-05-14T10:00:00Z",
          "status": "LN",
          "accounts": ["acc-1", "acc-2"],
          "institution_id": "BANK_OF_IRELAND_BOFIIE2D"
        }
        """
        let r = try JSONDecoder().decode(
            GoCardlessAPI.Requisition.self, from: Data(json.utf8))
        XCTAssertEqual(r.status, "LN")
        XCTAssertEqual(r.accounts.count, 2)
        XCTAssertEqual(r.institution_id, "BANK_OF_IRELAND_BOFIIE2D")
    }

    func test_transactionsResponseDecodes_bookedOnly() throws {
        let json = """
        {
          "transactions": {
            "booked": [
              {
                "transactionId": "tx-1",
                "bookingDate": "2026-05-12",
                "valueDate": "2026-05-12",
                "transactionAmount": { "amount": "-12.50", "currency": "EUR" },
                "creditorName": "TESCO EXPRESS CAMDEN",
                "remittanceInformationUnstructured": "Grocery shopping"
              }
            ],
            "pending": []
          }
        }
        """
        let resp = try JSONDecoder().decode(
            GoCardlessAPI.TransactionsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.transactions.booked.count, 1)
        let tx = resp.transactions.booked[0]
        XCTAssertEqual(tx.transactionAmount.amount, "-12.50")
        XCTAssertEqual(tx.creditorName, "TESCO EXPRESS CAMDEN")
    }

    func test_transactionsResponseDecodes_missingPendingIsFine() throws {
        // Banks differ on whether "pending" appears at all. Both
        // accepted.
        let json = """
        { "transactions": { "booked": [] } }
        """
        let resp = try JSONDecoder().decode(
            GoCardlessAPI.TransactionsResponse.self, from: Data(json.utf8))
        XCTAssertTrue(resp.transactions.booked.isEmpty)
        XCTAssertNil(resp.transactions.pending)
    }
}
