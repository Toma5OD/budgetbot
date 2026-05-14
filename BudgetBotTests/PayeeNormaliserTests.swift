import XCTest
@testable import BudgetBot

final class PayeeNormaliserTests: XCTestCase {

    func test_caseAndPunctuationCollapseToSameKey() {
        let k1 = PayeeNormaliser.key("Chemist Warehouse")
        let k2 = PayeeNormaliser.key("CHEMIST WAREHOUSE")
        let k3 = PayeeNormaliser.key("chemist-warehouse")
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1, k3)
    }

    func test_stripsCardStatementJunkSuffix() {
        // "Tesco 04 12345" — the trailing digit groups get stripped,
        // matching "Tesco". (Branch names like "Tesco Dublin" stay distinct
        // — that's intentional, the user can rename if needed.)
        XCTAssertEqual(
            PayeeNormaliser.key("Tesco 04 12345"),
            PayeeNormaliser.key("Tesco")
        )
        XCTAssertEqual(
            PayeeNormaliser.key("NETFLIX *MONTHLY"),
            PayeeNormaliser.key("Netflix")
        )
        XCTAssertEqual(
            PayeeNormaliser.key("Amazon #4242"),
            PayeeNormaliser.key("amazon")
        )
    }

    func test_branchNamesStayDistinct() {
        // We don't try to merge "Tesco Dublin" into "Tesco" — city/branch
        // tokens are too unreliable to strip blindly.
        XCTAssertNotEqual(
            PayeeNormaliser.key("Tesco Dublin"),
            PayeeNormaliser.key("Tesco")
        )
    }

    func test_stripsCorporateSuffixes() {
        XCTAssertEqual(
            PayeeNormaliser.key("Acme Limited"),
            PayeeNormaliser.key("Acme")
        )
        XCTAssertEqual(
            PayeeNormaliser.key("Acme Ltd"),
            PayeeNormaliser.key("Acme")
        )
    }

    func test_canonical_picksExistingSpelling() {
        let result = PayeeNormaliser.canonical(
            forKey: PayeeNormaliser.key("chemist warehouse"),
            in: ["Chemist Warehouse", "Tesco"],
            fallback: "CHEMIST WAREHOUSE"
        )
        XCTAssertEqual(result, "Chemist Warehouse",
                       "Should reuse the user-blessed spelling already in the database")
    }

    func test_canonical_fallsBackWhenNothingMatches() {
        let result = PayeeNormaliser.canonical(
            forKey: PayeeNormaliser.key("Boots Pharmacy"),
            in: ["Chemist Warehouse", "Tesco"],
            fallback: "Boots Pharmacy"
        )
        XCTAssertEqual(result, "Boots Pharmacy")
    }

    func test_distinctMerchantsKeepDistinctKeys() {
        XCTAssertNotEqual(
            PayeeNormaliser.key("Tesco"),
            PayeeNormaliser.key("Lidl")
        )
    }
}
