import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class SeriesLinkerTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private func makeNetflixRule(_ ctx: ModelContext) -> RecurringRule {
        let r = RecurringRule(
            payeePattern: "netflix",                 // PayeeNormaliser.key("Netflix")
            displayName: "Netflix",
            expectedAmount: -18.99,
            currency: "EUR",
            cadence: .monthly,
            firstSeen: .distantPast,
            lastSeen: .now,
            occurrences: 5
        )
        ctx.insert(r)
        return r
    }

    private func makeTx(_ ctx: ModelContext,
                        payee: String,
                        amount: Decimal,
                        daysAgo: Int,
                        rating: Int? = nil) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let t = Transaction(
            date: date, amount: amount, currency: "EUR",
            payee: payee, confirmed: true,
            hindsightRating: rating,
            hindsightRatedAt: rating == nil ? nil : .now
        )
        ctx.insert(t)
        return t
    }

    func test_backlink_stampsRuleIDOnMatchingTransactions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let t1 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30)
        let t2 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 60)
        let unrelated = makeTx(ctx, payee: "Tesco", amount: -25.00, daysAgo: 15)
        try ctx.save()

        SeriesLinker.backlink(rules: [rule], transactions: [t1, t2, unrelated])

        XCTAssertEqual(t1.recurringRuleID, rule.id)
        XCTAssertEqual(t2.recurringRuleID, rule.id)
        XCTAssertNil(unrelated.recurringRuleID,
                     "Tesco isn't Netflix — must not get the Netflix rule id")
    }

    func test_backlink_propagatesRatingFromAnyRatedSiblingInSeries() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let t1 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30, rating: 2)
        let t2 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 60)
        let t3 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 90)
        try ctx.save()

        SeriesLinker.backlink(rules: [rule], transactions: [t1, t2, t3])

        XCTAssertEqual(t1.hindsightRating, 2, "Rated tx should be unchanged")
        XCTAssertEqual(t2.hindsightRating, 2, "Unrated sibling inherits the rating")
        XCTAssertEqual(t3.hindsightRating, 2, "Every unrated sibling inherits")
    }

    func test_backlink_doesNotOverwriteAlreadyRatedSiblings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let t1 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30, rating: 2)
        let t2 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 60, rating: 5)
        try ctx.save()

        SeriesLinker.backlink(rules: [rule], transactions: [t1, t2])

        XCTAssertEqual(t1.hindsightRating, 2)
        XCTAssertEqual(t2.hindsightRating, 5,
                       "A sibling that already had a different rating must keep it")
    }

    func test_backlink_respectsAmountTolerance() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)   // expects -18.99

        let withinTolerance = makeTx(ctx, payee: "Netflix",
                                     amount: -19.50, daysAgo: 30)   // ~2.7% off
        let outsideTolerance = makeTx(ctx, payee: "Netflix",
                                      amount: -22.00, daysAgo: 60)  // ~16% off
        try ctx.save()

        SeriesLinker.backlink(rules: [rule], transactions: [withinTolerance, outsideTolerance])

        XCTAssertEqual(withinTolerance.recurringRuleID, rule.id)
        XCTAssertNil(outsideTolerance.recurringRuleID,
                     "Amount too far from expected — must not be linked")
    }

    func test_propagate_copiesRatingToUnratedSiblings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let t1 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30)
        let t2 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 60)
        let t3 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 90)
        t1.recurringRuleID = rule.id
        t2.recurringRuleID = rule.id
        t3.recurringRuleID = rule.id
        try ctx.save()

        // User rates one of them via the deck.
        t1.hindsightRating = 1
        t1.hindsightRatedAt = .now

        let count = SeriesLinker.propagate(ratingFrom: t1, in: ctx)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(t2.hindsightRating, 1)
        XCTAssertEqual(t3.hindsightRating, 1)
    }

    func test_propagate_doesNotTouchAlreadyRatedSiblings() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let t1 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30)
        let t2 = makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 60, rating: 4)
        t1.recurringRuleID = rule.id
        t2.recurringRuleID = rule.id
        try ctx.save()

        t1.hindsightRating = 1
        t1.hindsightRatedAt = .now
        let count = SeriesLinker.propagate(ratingFrom: t1, in: ctx)

        XCTAssertEqual(count, 0,
                       "Already-rated siblings shouldn't be reset by a propagation pass")
        XCTAssertEqual(t2.hindsightRating, 4)
    }

    func test_seriesSize_countsSiblingsExcludingSelf() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rule = makeNetflixRule(ctx)

        let txs = (0..<5).map { i in
            makeTx(ctx, payee: "Netflix", amount: -18.99, daysAgo: 30 * (i + 1))
        }
        for tx in txs { tx.recurringRuleID = rule.id }
        try ctx.save()

        XCTAssertEqual(SeriesLinker.seriesSize(for: txs[0], in: ctx), 4,
                       "Series of 5 → 4 other siblings")
    }
}
