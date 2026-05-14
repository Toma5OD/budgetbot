import Foundation
import SwiftData

// ──────────────────────────────────────────────────────────────────────────
// TEMPORARY — REMOVE BEFORE 1.0
//
// One-shot seeder that wipes the database and inserts a fake user with
// ~3 months of synthetic activity. The product currently lacks any
// long-running organic data (every schema rewrite during dev nukes the
// store), so this exists purely so screens like Analytics, Subscriptions
// and Hall of Shame have something to render during dev demos.
//
// Best practice for "temp":
//   • single isolated file — drop the file + the Settings entry to delete
//   • pure functions, no shared state
//   • deterministic-ish: same persona every run, jittered amounts
//   • surfaced only via Settings → Developer → "Load demo data" (gated by
//     a destructive confirmation dialog)
//   • does not call any network APIs
// ──────────────────────────────────────────────────────────────────────────
enum DemoDataSeeder {

    /// Wipes existing user data then inserts the demo persona. The caller
    /// is responsible for confirming with the user before invoking — this
    /// function is irreversibly destructive.
    @MainActor
    static func wipeAndSeed(in context: ModelContext) throws {
        try wipe(in: context)
        try seed(in: context)
        try context.save()
    }

    /// Removes every persisted user record. Categories are reseeded by
    /// `seed`, so we wipe them too for a clean slate.
    @MainActor
    static func wipe(in context: ModelContext) throws {
        for type: any PersistentModel.Type in [
            Split.self, Transaction.self, Attachment.self, AIRecommendation.self,
            Account.self, TxCategory.self, RecurringRule.self, CaptureJob.self,
            FXRateSnapshot.self, UserProfile.self
        ] {
            try context.delete(model: type)
        }
    }

    /// Inserts a self-contained demo persona. Idempotency is the caller's
    /// problem — call `wipe` first if you need a clean slate.
    @MainActor
    static func seed(in context: ModelContext) throws {
        // ── Profile ────────────────────────────────────────────────────
        let profile = UserProfile(
            appleUserID: "demo.user.\(UUID().uuidString)",
            displayName: "Sam Sample",
            email: "sam@budgetbot.demo",
            defaultCurrency: "EUR",
            baseCurrency: "EUR",
            monthlyBudget: 2_400
        )
        context.insert(profile)

        // ── Categories ─────────────────────────────────────────────────
        var byName: [String: TxCategory] = [:]
        for (name, kind, emoji) in TxCategory.defaults {
            let c = TxCategory(name: name, kind: kind, emoji: emoji)
            context.insert(c)
            byName[name] = c
        }

        // ── Accounts ───────────────────────────────────────────────────
        let revolut = Account(name: "Revolut", kind: .bank, institution: "Revolut",
                              currency: "EUR", openingBalance: 1_850)
        let wallet  = Account(name: "Cash Wallet", kind: .cash,
                              currency: "EUR", openingBalance: 80)
        let amex    = Account(name: "Amex Travel", kind: .credit, institution: "American Express",
                              currency: "USD", openingBalance: 0)
        context.insert(revolut); context.insert(wallet); context.insert(amex)

        // ── Transactions ───────────────────────────────────────────────
        // Deterministic-ish: seed RNG from a fixed value so demo looks
        // similar across runs but not perfectly identical.
        var rng = SeededGenerator(seed: 0xBEEF_FEED)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)

        // Salary — monthly, +€3,200, into Revolut.
        for monthsAgo in 0..<4 {
            if let d = cal.date(byAdding: .month, value: -monthsAgo, to: cal.date(bySetting: .day, value: 1, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * 9),
                           payee: "ACME Corp Payroll",
                           amount: 3_200, currency: "EUR",
                           account: revolut,
                           category: byName["Salary"],
                           method: .card,
                           note: "Monthly salary")
            }
        }

        // Rent — monthly, -€1,200.
        for monthsAgo in 0..<4 {
            if let d = cal.date(byAdding: .month, value: -monthsAgo, to: cal.date(bySetting: .day, value: 3, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: d,
                           payee: "Landlord — Apt 4B",
                           amount: -1_200, currency: "EUR",
                           account: revolut,
                           category: byName["Rent"],
                           method: .card)
            }
        }

        // Recurring subs — Netflix, Spotify, Gym, mobile, internet.
        struct Sub { let payee: String; let amount: Decimal; let day: Int; let cat: String }
        let subs: [Sub] = [
            Sub(payee: "Netflix",          amount: -12.99, day: 7,  cat: "Streaming"),
            Sub(payee: "Spotify Premium",  amount: -9.99,  day: 14, cat: "Streaming"),
            Sub(payee: "Anytime Fitness",  amount: -39.00, day: 5,  cat: "Other Subscriptions"),
            Sub(payee: "Three Mobile",     amount: -25.00, day: 18, cat: "Mobile Plan"),
            Sub(payee: "Virgin Media",     amount: -45.00, day: 22, cat: "Internet")
        ]
        for sub in subs {
            for monthsAgo in 0..<3 {
                if let d = cal.date(byAdding: .month, value: -monthsAgo,
                                    to: cal.date(bySetting: .day, value: sub.day, of: today) ?? today) {
                    _ = makeTx(in: context,
                               date: d, payee: sub.payee,
                               amount: sub.amount, currency: "EUR",
                               account: revolut,
                               category: byName[sub.cat],
                               method: .card)
                }
            }
        }

        // Groceries — every 4-5 days, jitter €30..€95.
        for daysAgo in stride(from: 1, to: 90, by: 4) {
            let jitter = Decimal(Int.random(in: -10...20, using: &rng))
            let base = Decimal(Int.random(in: 35...75, using: &rng))
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                .addingTimeInterval(Double(Int.random(in: 9...19, using: &rng)) * 3600)
            let payee = ["Lidl", "Tesco", "Aldi", "Dunnes Stores"].randomElement(using: &rng)!
            _ = makeTx(in: context,
                       date: date, payee: payee,
                       amount: -(base + jitter), currency: "EUR",
                       account: revolut,
                       category: byName["Groceries"],
                       method: .card,
                       cardBrand: "Visa", cardLast4: "4242")
        }

        // One grocery shop with splits (groceries + alcohol).
        if let d = cal.date(byAdding: .day, value: -7, to: today) {
            let tx = makeTx(in: context,
                            date: d.addingTimeInterval(3600 * 18),
                            payee: "Tesco",
                            amount: -64.20, currency: "EUR",
                            account: revolut,
                            category: nil,
                            method: .card,
                            cardBrand: "Visa", cardLast4: "4242",
                            note: "Weekend shop")
            context.insert(Split(description: "Groceries",
                                 amount: -48.20,
                                 category: byName["Groceries"],
                                 transaction: tx))
            context.insert(Split(description: "Wine",
                                 amount: -16.00,
                                 category: byName["Alcohol"],
                                 transaction: tx))
        }

        // Coffee — Mon/Wed/Fri last 4 weeks.
        for week in 0..<4 {
            for weekday in [2, 4, 6] {       // Mon, Wed, Fri
                if let base = cal.date(byAdding: .day, value: -(week * 7), to: today),
                   let d = cal.date(bySetting: .weekday, value: weekday, of: base),
                   d <= today {
                    let amount = Decimal(Int.random(in: 30...55, using: &rng)) / 10
                    _ = makeTx(in: context,
                               date: d.addingTimeInterval(3600 * 8.5),
                               payee: ["Starbucks", "Insomnia", "Java Republic"].randomElement(using: &rng)!,
                               amount: -amount, currency: "EUR",
                               account: wallet,
                               category: byName["Coffee"],
                               method: .cash)
                }
            }
        }

        // Restaurants & dining out — a few per month.
        let diners = [
            ("Manifesto",  -34.50, 18),
            ("Pi Pizza",   -22.00, 32),
            ("Yamamori",   -58.00, 9),
            ("Bunsen",     -19.50, 45),
            ("Klaw",       -94.00, 60)
        ]
        for (name, amt, daysAgo) in diners {
            if let d = cal.date(byAdding: .day, value: -daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * 20),
                           payee: name,
                           amount: Decimal(amt), currency: "EUR",
                           account: revolut,
                           category: byName["Dining"],
                           method: .card,
                           cardBrand: "Visa", cardLast4: "4242")
            }
        }

        // Travel — one USD trip on the Amex.
        if let d = cal.date(byAdding: .day, value: -38, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "United Airlines",
                       amount: -310, currency: "USD",
                       account: amex,
                       category: byName["Travel"],
                       method: .card,
                       cardBrand: "Amex", cardLast4: "1009",
                       fxRateToBase: 0.92, fxBase: "EUR")
            if let d2 = cal.date(byAdding: .day, value: -36, to: today) {
                _ = makeTx(in: context,
                           date: d2, payee: "Marriott Times Square",
                           amount: -420, currency: "USD",
                           account: amex,
                           category: byName["Travel"],
                           method: .card,
                           cardBrand: "Amex", cardLast4: "1009",
                           fxRateToBase: 0.92, fxBase: "EUR")
            }
        }

        // ── Hall of Shame — a handful of regrettable purchases. ────────
        struct Regret {
            let payee: String; let amount: Decimal; let daysAgo: Int
            let cat: String; let emoji: String; let note: String
        }
        let regrets: [Regret] = [
            Regret(payee: "Domino's Pizza",   amount: -38.50, daysAgo: 6,
                   cat: "Dining", emoji: "🍕",
                   note: "Ordered at 2:47 am. Why."),
            Regret(payee: "Amazon",           amount: -127.00, daysAgo: 21,
                   cat: "Shopping", emoji: "🛍️",
                   note: "Air fryer accessories I haven't touched"),
            Regret(payee: "Bookies App",      amount: -50.00, daysAgo: 31,
                   cat: "Entertainment", emoji: "🎰",
                   note: "Bet on a team I'd never heard of"),
            Regret(payee: "Uber",             amount: -22.00, daysAgo: 10,
                   cat: "Taxi & Ride-share", emoji: "🚕",
                   note: "Walked back the other way next morning"),
            Regret(payee: "The Long Hall",    amount: -76.00, daysAgo: 17,
                   cat: "Alcohol", emoji: "🍻",
                   note: "Rounds for people I just met"),
            Regret(payee: "ASOS",             amount: -89.00, daysAgo: 44,
                   cat: "Clothing", emoji: "🛍️",
                   note: "Sizing was off, never returned")
        ]
        for r in regrets {
            if let d = cal.date(byAdding: .day, value: -r.daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * Double(Int.random(in: 1...23, using: &rng))),
                           payee: r.payee,
                           amount: r.amount, currency: "EUR",
                           account: revolut,
                           category: byName[r.cat],
                           method: .card,
                           cardBrand: "Visa", cardLast4: "4242",
                           note: r.note,
                           isRegret: true,
                           regretEmoji: r.emoji,
                           regretNote: r.note)
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func makeTx(
        in context: ModelContext,
        date: Date,
        payee: String,
        amount: Decimal,
        currency: String,
        account: Account?,
        category: TxCategory?,
        method: Transaction.PaymentMethod,
        cardBrand: String? = nil,
        cardLast4: String? = nil,
        fxRateToBase: Decimal? = nil,
        fxBase: String? = nil,
        note: String? = nil,
        isRegret: Bool = false,
        regretEmoji: String? = nil,
        regretNote: String? = nil
    ) -> Transaction {
        let tx = Transaction(
            date: date,
            amount: amount,
            currency: currency,
            payee: payee,
            note: note,
            confirmed: true,
            aiExtracted: false,
            paymentMethod: method,
            cardBrand: cardBrand,
            cardLast4: cardLast4,
            fxRateToBase: fxRateToBase,
            fxBaseCurrency: fxBase,
            isRegret: isRegret,
            regretEmoji: regretEmoji,
            regretNote: regretNote,
            account: account,
            category: category
        )
        context.insert(tx)
        return tx
    }
}

/// Tiny deterministic PRNG so demo amounts/payees feel varied without being
/// truly random across runs. Mulberry32; good enough for cosmetic jitter.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt32
    init(seed: UInt32) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x6D2B79F5
        var z = state
        z = (z ^ (z &>> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z &>> 7)) &* (z | 61))
        let lo = UInt64(z ^ (z &>> 14))
        // Spread to 64 bits with a second step.
        state &+= 0x9E37_79B9
        var w = state
        w = (w ^ (w &>> 13)) &* 0x85EB_CA6B
        let hi = UInt64(w ^ (w &>> 16))
        return (hi << 32) | lo
    }
}
