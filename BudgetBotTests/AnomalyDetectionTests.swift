import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class AnomalyDetectionTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory()
    }

    private let identityConvert: AnalyticsMetrics.Converter = { amt, _, _ in amt }

    private func tx(_ ctx: ModelContext, amount: Decimal, payee: String, daysAgo: Int) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let t = Transaction(date: date, amount: amount, currency: "EUR",
                            payee: payee, confirmed: true)
        ctx.insert(t)
        return t
    }

    func test_uniformSpending_producesNoAnomalies() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 8 consistent €4 coffees, none unusual.
        for daysAgo in [3, 5, 10, 18, 25, 35, 45, 60] {
            _ = tx(ctx, amount: -4, payee: "Insomnia", daysAgo: daysAgo)
        }
        let anomalies = AnalyticsMetrics.anomalies(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertTrue(anomalies.isEmpty,
                      "Uniform spend at a merchant should never trip the anomaly detector")
    }

    func test_recentSpikeOverThreshold_flagsTheTransaction() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // 5 priors at €30 in the older window.
        for daysAgo in [25, 40, 55, 70, 80] {
            _ = tx(ctx, amount: -30, payee: "Tesco", daysAgo: daysAgo)
        }
        // One recent spike at €120 (4× typical).
        let spike = tx(ctx, amount: -120, payee: "Tesco", daysAgo: 3)

        let anomalies = AnalyticsMetrics.anomalies(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)

        XCTAssertEqual(anomalies.count, 1)
        XCTAssertEqual(anomalies.first?.transaction.id, spike.id)
        XCTAssertEqual(anomalies.first?.typical, 30)
        XCTAssertEqual(anomalies.first?.factor ?? 0, 4.0, accuracy: 0.01)
    }

    func test_insufficientPriors_doesNotFlag() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Only 2 priors — below the minPriors=3 threshold.
        _ = tx(ctx, amount: -5, payee: "New Spot", daysAgo: 30)
        _ = tx(ctx, amount: -5, payee: "New Spot", daysAgo: 50)
        // Big recent visit — should NOT be flagged because we don't have
        // enough history to know what "typical" looks like.
        _ = tx(ctx, amount: -200, payee: "New Spot", daysAgo: 3)

        let anomalies = AnalyticsMetrics.anomalies(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertTrue(anomalies.isEmpty,
                      "We require ≥3 priors so a fresh merchant can't define its own baseline")
    }

    func test_anomaliesSortedByFactorDescending() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Two merchants, both with consistent priors.
        for daysAgo in [25, 40, 55, 70] {
            _ = tx(ctx, amount: -10, payee: "Cafe A", daysAgo: daysAgo)
            _ = tx(ctx, amount: -20, payee: "Cafe B", daysAgo: daysAgo)
        }
        // Spikes: Cafe A 3× typical, Cafe B 5× typical.
        _ = tx(ctx, amount: -30,  payee: "Cafe A", daysAgo: 2)
        _ = tx(ctx, amount: -100, payee: "Cafe B", daysAgo: 4)

        let anomalies = AnalyticsMetrics.anomalies(
            in: try ctx.fetch(FetchDescriptor<Transaction>()),
            base: "EUR", convert: identityConvert)
        XCTAssertEqual(anomalies.count, 2)
        XCTAssertEqual(anomalies.first?.transaction.payee, "Cafe B",
                       "Biggest factor wedge should appear first")
        XCTAssertEqual(anomalies.last?.transaction.payee, "Cafe A")
    }
}
