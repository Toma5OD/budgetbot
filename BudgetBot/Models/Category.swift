import Foundation
import SwiftData

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    var id: String { rawValue }
}

@Model
final class TxCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var emoji: String
    var colorHex: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: CategoryKind,
        emoji: String = "🧾",
        colorHex: String = "#34A853",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.emoji = emoji
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    static let defaults: [(String, CategoryKind, String)] = [
        ("Groceries",      .expense, "🛒"),
        ("Dining",         .expense, "🍔"),
        ("Coffee",         .expense, "☕️"),
        ("Transport",      .expense, "🚌"),
        ("Fuel",           .expense, "⛽️"),
        ("Rent",           .expense, "🏠"),
        ("Utilities",      .expense, "💡"),
        ("Subscriptions",  .expense, "🔁"),
        ("Entertainment",  .expense, "🎬"),
        ("Shopping",       .expense, "🛍️"),
        ("Health",         .expense, "🩺"),
        ("Travel",         .expense, "✈️"),
        ("Other Expense",  .expense, "🧾"),
        ("Salary",         .income,  "💼"),
        ("Freelance",      .income,  "🧑‍💻"),
        ("Refund",         .income,  "↩️"),
        ("Gift",           .income,  "🎁"),
        ("Interest",       .income,  "🏦"),
        ("Other Income",   .income,  "💰")
    ]
}
