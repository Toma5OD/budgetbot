import Foundation
import SwiftData

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    var id: String { rawValue }
}

@Model
final class TxCategory {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = CategoryKind.expense.rawValue
    var emoji: String = "🧾"
    var colorHex: String = "#34A853"
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]?

    @Relationship(deleteRule: .nullify, inverse: \Split.category)
    var splits: [Split]?

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category)
    var recurringRules: [RecurringRule]?

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

    /// Default category catalogue. Grouped here for editorial sanity; flat at
    /// runtime. The AI prompt is fed this same list so the model picks from
    /// a controlled vocabulary instead of inventing one-off labels.
    static let defaults: [(String, CategoryKind, String)] = [
        // Food & drink
        ("Groceries",          .expense, "🛒"),
        ("Dining",             .expense, "🍔"),
        ("Coffee",             .expense, "☕️"),
        ("Alcohol",            .expense, "🍷"),

        // Transport
        ("Fuel",               .expense, "⛽️"),
        ("Public Transport",   .expense, "🚌"),
        ("Taxi & Ride-share",  .expense, "🚕"),
        ("Parking",            .expense, "🅿️"),
        ("Car Maintenance",    .expense, "🔧"),

        // Recurring bills
        ("Rent",               .expense, "🏠"),
        ("Mortgage",           .expense, "🏘️"),
        ("Electricity",        .expense, "⚡️"),
        ("Heating & Gas",      .expense, "🔥"),
        ("Water",              .expense, "💧"),
        ("Internet",           .expense, "🌐"),
        ("Mobile Plan",        .expense, "📱"),
        ("Streaming",          .expense, "📺"),
        ("Other Subscriptions",.expense, "🔁"),
        ("Insurance",          .expense, "🛡️"),
        ("Taxes",              .expense, "🧾"),
        ("Bank Fees",          .expense, "🏦"),
        ("Loan Payment",       .expense, "💸"),

        // Health
        ("Pharmacy",           .expense, "💊"),
        ("Medical",            .expense, "🩺"),
        ("Personal Care",      .expense, "💇"),

        // Home & family
        ("Home & Garden",      .expense, "🏡"),
        ("Pets",               .expense, "🐾"),
        ("Childcare",          .expense, "👶"),

        // Lifestyle
        ("Entertainment",      .expense, "🎬"),
        ("Shopping",           .expense, "🛍️"),
        ("Clothing",           .expense, "👕"),
        ("Electronics",        .expense, "🔌"),
        ("Books & Media",      .expense, "📚"),
        ("Hobbies",            .expense, "🎨"),
        ("Travel",             .expense, "✈️"),
        ("Education",          .expense, "🎓"),
        ("Charity",            .expense, "🤝"),
        ("Gifts Given",        .expense, "🎀"),

        // Catch-all
        ("Cash Withdrawal",    .expense, "💵"),
        ("Other Expense",      .expense, "🟫"),

        // Income
        ("Salary",             .income,  "💼"),
        ("Freelance",          .income,  "🧑‍💻"),
        ("Investment Returns", .income,  "📈"),
        ("Refund",             .income,  "↩️"),
        ("Gift Received",      .income,  "🎁"),
        ("Interest",           .income,  "🏛️"),
        ("Other Income",       .income,  "💰")
    ]
}
