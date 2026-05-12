import XCTest
import SwiftData
@testable import BudgetBot

@MainActor
final class AccountBalanceTests: XCTestCase {

    func test_emptyAccount_balanceEqualsOpeningBalance() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext
        let a = Account(name: "Wallet", kind: .cash, openingBalance: 100)
        ctx.insert(a)
        try ctx.save()
        XCTAssertEqual(a.balance, 100)
    }

    func test_balanceSumsConfirmedTransactionsOnly() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let a = Account(name: "Checking", kind: .bank, openingBalance: 1000)
        ctx.insert(a)

        // Confirmed
        ctx.insert(Transaction(amount: -150, payee: "Rent", confirmed: true,  account: a))
        ctx.insert(Transaction(amount:  +50, payee: "Refund", confirmed: true,  account: a))
        // Unconfirmed — should NOT count
        ctx.insert(Transaction(amount: -999, payee: "Pending", confirmed: false, account: a))
        try ctx.save()

        XCTAssertEqual(a.balance, 1000 - 150 + 50)
    }

    func test_cashAccount_tracksPhysicalMoney() throws {
        let container = try PersistenceController.makeInMemory()
        let ctx = container.mainContext

        let wallet = Account(name: "Wallet", kind: .cash, openingBalance: 200)
        ctx.insert(wallet)
        ctx.insert(Transaction(amount: -20, payee: "Coffee", confirmed: true, account: wallet))
        ctx.insert(Transaction(amount: -35, payee: "Lunch",  confirmed: true, account: wallet))
        try ctx.save()
        XCTAssertEqual(wallet.balance, 200 - 20 - 35)
    }
}
