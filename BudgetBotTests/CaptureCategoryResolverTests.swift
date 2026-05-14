import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class CaptureCategoryResolverTests: XCTestCase {

    private func draft(suggested: String? = nil, newCat: String? = nil, amount: Decimal = -10) -> ExtractedDraft {
        ExtractedDraft(
            date: .now, amount: amount, currency: "EUR",
            payee: "X", note: nil,
            suggestedCategory: suggested,
            newCategory: newCat,
            accountHint: nil,
            paymentMethod: .unknown,
            lineItems: [],
            confidence: 0.9
        )
    }

    private func makeCategories() -> [TxCategory] {
        TxCategory.defaults.map { TxCategory(name: $0.0, kind: $0.1, emoji: $0.2) }
    }

    func test_exactSuggestedCategory_matches() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: "Pharmacy"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Pharmacy")
    }

    func test_caseInsensitiveSuggestedMatches() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: "groceries"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Groceries")
    }

    func test_fuzzyPluralMatches() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: "Pharmacies"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Pharmacy")
    }

    func test_newCategory_createsRowWhenNoMatch() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let countBefore = cats.count

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: nil, newCat: "Vape Shop"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Vape Shop")
        XCTAssertEqual(cats.count, countBefore + 1,
                       "A new category row should have been inserted")
    }

    func test_newCategory_reusesExistingByFuzzyMatchInsteadOfCreating() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let countBefore = cats.count

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: nil, newCat: "Pharmacy & Drugs"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Pharmacy",
                       "Fuzzy contains match should reuse the existing category")
        XCTAssertEqual(cats.count, countBefore,
                       "No new row should have been inserted")
    }

    func test_newCategory_titleCasesIncomingName() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(suggested: nil, newCat: "vape shop"),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(resolved?.name, "Vape Shop")
    }

    func test_newCategory_inheritsCorrectKindFromSignedAmount() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let expense = CaptureCategoryResolver.resolve(
            draft: draft(newCat: "Cryptocurrency Loss", amount: -50),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(expense?.kind, .expense)

        let income = CaptureCategoryResolver.resolve(
            draft: draft(newCat: "Tax Rebate", amount: 200),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertEqual(income?.kind, .income)
    }

    func test_nothingFromAI_returnsNil() throws {
        let container = try PersistenceController.makeInMemory()
        var cats = makeCategories()
        for c in cats { container.mainContext.insert(c) }

        let resolved = CaptureCategoryResolver.resolve(
            draft: draft(),
            in: &cats,
            context: container.mainContext
        )
        XCTAssertNil(resolved, "If AI didn't propose anything, leave it uncategorised")
    }
}
