import Foundation
import SwiftData

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case bank
    case savings
    case cash
    case credit
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bank: return "Bank"
        case .savings: return "Savings"
        case .cash: return "Cash"
        case .credit: return "Credit"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .savings: return "banknote.fill"
        case .cash: return "dollarsign.circle.fill"
        case .credit: return "creditcard.fill"
        case .other: return "wallet.pass.fill"
        }
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.bank.rawValue
    var institution: String?
    var currency: String = "EUR"
    var openingBalance: Decimal = 0
    var archived: Bool = false
    var createdAt: Date = Date.now

    // To-many relationships must be optional for CloudKit. `?? []` at every
    // read site keeps the call-sites readable.
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]?

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.account)
    var recurringRules: [RecurringRule]?

    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        institution: String? = nil,
        currency: String = "USD",
        openingBalance: Decimal = 0,
        archived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.institution = institution
        self.currency = currency
        self.openingBalance = openingBalance
        self.archived = archived
        self.createdAt = createdAt
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var balance: Decimal {
        openingBalance + (transactions ?? [])
            .filter { $0.confirmed }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
}
