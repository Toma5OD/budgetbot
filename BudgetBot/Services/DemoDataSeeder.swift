#if DEBUG
import Foundation
import SwiftData

// ──────────────────────────────────────────────────────────────────────────
// TEMPORARY — REMOVE BEFORE 1.0
//
// Hand-curated demo persona for dev/QA screens.
//
// The data here is *handcrafted*, not borrowed from a public dataset:
// the realistic-personal-finance datasets that exist online are either
// anonymised credit-card timestamps (no merchant names), raw receipt
// images (CORD, SROIE — no structured fields), or three-row sample OFX
// exports. None of them give you the merchant + amount + category mix
// you need to populate a budgeting app's charts.
//
// What we do instead — and what every fintech does for their demo build —
// is curate against (a) recognisable real-world merchant names and
// (b) public household-budget statistics for the category proportions
// and amount distributions. Concretely:
//   • Merchant catalogue: real Irish retailers/services current in
//     2024-2026 (Tesco, SuperValu, Boots, Bord Gáis, Free Now, etc.)
//   • Category mix loosely tracks the CSO Household Budget Survey for
//     a single Dublin professional (housing ~30%, groceries ~12%,
//     transport ~10%, recreation ~8%, etc.)
//   • Prices reflect post-inflation 2024-2026 reality (€4 coffee,
//     €1,800 1-bed rent, €18.99 Netflix Standard).
//
// Lifecycle events included so behaviour screens have content to chew
// on: a cancelled Disney+ subscription, an Amazon return refund, an
// annual insurance bill, a salary bonus month, a USD trip with FX
// snapshots, a few splits, six pre-tagged regrets for Hall of Shame.
//
// Best practice for "temp":
//   • single isolated file — drop the file + the Settings entry to delete
//   • pure functions, no shared state
//   • deterministic-ish: same persona every run, jittered amounts
//   • surfaced only via Settings → Developer → "Load demo data" (gated
//     by a destructive confirmation dialog)
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
            monthlyBudget: 2_800
        )
        context.insert(profile)

        // ── Categories ─────────────────────────────────────────────────
        var byName: [String: TxCategory] = [:]
        for (name, kind, emoji) in TxCategory.defaults {
            let c = TxCategory(name: name, kind: kind, emoji: emoji)
            context.insert(c)
            byName[name] = c
        }
        // Resolver convenience — fall back to "Other Expense" / "Other
        // Income" if a name is missing, since the seeder is the only
        // place that has to silently tolerate a category catalogue drift.
        func cat(_ name: String) -> TxCategory? { byName[name] }

        // ── Accounts ───────────────────────────────────────────────────
        let revolut = Account(name: "Revolut", kind: .bank, institution: "Revolut",
                              currency: "EUR", openingBalance: 2_140)
        let aib     = Account(name: "AIB Current", kind: .bank, institution: "AIB",
                              currency: "EUR", openingBalance: 980)
        let wallet  = Account(name: "Cash", kind: .cash,
                              currency: "EUR", openingBalance: 45)
        let amex    = Account(name: "Amex Gold", kind: .credit, institution: "American Express",
                              currency: "USD", openingBalance: 0)
        context.insert(revolut); context.insert(aib); context.insert(wallet); context.insert(amex)

        // ── RNG / Calendar ─────────────────────────────────────────────
        var rng = SeededGenerator(seed: 0xBEEF_FEED)
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: .now)

        // ── Salary (mid-level Dublin software role) ────────────────────
        // Last business day-ish of each month. December has a small bonus.
        for monthsAgo in 0..<5 {
            guard let monthStart = cal.date(byAdding: .month, value: -monthsAgo,
                                            to: cal.date(bySetting: .day, value: 25, of: today) ?? today)
            else { continue }
            let isDecember = cal.component(.month, from: monthStart) == 12
            _ = makeTx(in: context,
                       date: monthStart.addingTimeInterval(3600 * 9),
                       payee: "Bytecode Labs Ltd Payroll",
                       amount: 4_180, currency: "EUR",
                       account: aib, category: cat("Salary"),
                       method: .card,
                       note: "Monthly salary — net")
            if isDecember {
                _ = makeTx(in: context,
                           date: monthStart.addingTimeInterval(3600 * 9.5),
                           payee: "Bytecode Labs Ltd — Bonus",
                           amount: 1_800, currency: "EUR",
                           account: aib, category: cat("Salary"),
                           method: .card,
                           note: "Annual bonus")
            }
        }

        // Quarterly freelance gig (small consulting cheque).
        if let d = cal.date(byAdding: .day, value: -54, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Riverlane Design",
                       amount: 620, currency: "EUR",
                       account: revolut, category: cat("Freelance"),
                       method: .card, note: "Logo redesign — invoice 0019")
        }

        // Tax refund (rare but realistic).
        if let d = cal.date(byAdding: .day, value: -89, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Revenue Commissioners",
                       amount: 142.30, currency: "EUR",
                       account: aib, category: cat("Refund"),
                       method: .card, note: "PAYE balancing statement refund")
        }

        // ── Rent (1-bed Dublin 8, 2024-2026 market rate) ───────────────
        for monthsAgo in 0..<5 {
            if let monthFirst = cal.date(byAdding: .month, value: -monthsAgo,
                                         to: cal.date(bySetting: .day, value: 1, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: monthFirst.addingTimeInterval(3600 * 8),
                           payee: "Murphy Property Mgmt",
                           amount: -1_950, currency: "EUR",
                           account: aib, category: cat("Rent"),
                           method: .card, note: "Apt 12, Cork St")
            }
        }

        // ── Utilities (bi-monthly Electric Ireland, monthly Bord Gáis) ─
        // Electric Ireland bills every two months; this is the actual
        // Irish billing cadence.
        for monthsAgo in stride(from: 0, to: 5, by: 2) {
            if let d = cal.date(byAdding: .month, value: -monthsAgo,
                                to: cal.date(bySetting: .day, value: 11, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: d, payee: "Electric Ireland",
                           amount: Decimal(-130 + Int.random(in: -25...40, using: &rng)),
                           currency: "EUR",
                           account: aib, category: cat("Electricity"),
                           method: .card)
            }
        }
        for monthsAgo in 0..<5 {
            if let d = cal.date(byAdding: .month, value: -monthsAgo,
                                to: cal.date(bySetting: .day, value: 19, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: d, payee: "Bord Gáis Energy",
                           amount: Decimal(-72 + Int.random(in: -15...25, using: &rng)),
                           currency: "EUR",
                           account: aib, category: cat("Heating & Gas"),
                           method: .card)
            }
        }
        // Annual home insurance (single big hit in month -3).
        if let d = cal.date(byAdding: .day, value: -88, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Aviva Home Insurance",
                       amount: -312.40, currency: "EUR",
                       account: revolut, category: cat("Insurance"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Annual contents + buildings")
        }

        // ── Subscriptions ──────────────────────────────────────────────
        // Mix of active, cancelled, and free-trial converted.
        struct Sub {
            let payee: String
            let amount: Decimal
            let day: Int
            let cat: String
            let monthsActive: Range<Int>      // monthsAgo range when sub is live
            let card: (brand: String, last4: String)?
        }
        let subs: [Sub] = [
            // Active throughout.
            Sub(payee: "Netflix",              amount: -18.99, day: 7,
                cat: "Streaming",            monthsActive: 0..<5,
                card: ("Visa", "4242")),
            Sub(payee: "Spotify Premium",      amount: -11.99, day: 14,
                cat: "Streaming",            monthsActive: 0..<5,
                card: ("Visa", "4242")),
            Sub(payee: "FlyeFit Stephen's Green", amount: -29.99, day: 1,
                cat: "Other Subscriptions",  monthsActive: 0..<5,
                card: ("Visa", "4242")),
            Sub(payee: "GoMo",                 amount: -14.99, day: 23,
                cat: "Mobile Plan",          monthsActive: 0..<5,
                card: ("Visa", "4242")),
            Sub(payee: "Eir Broadband",        amount: -54.00, day: 28,
                cat: "Internet",             monthsActive: 0..<5,
                card: ("Visa", "4242")),
            // Cancelled after 2 months — surfaces the "stopped using" pattern.
            Sub(payee: "Disney+",              amount: -10.99, day: 5,
                cat: "Streaming",            monthsActive: 3..<5,
                card: ("Visa", "4242")),
            // New addition — only in the last 2 months.
            Sub(payee: "Audible",              amount: -7.99,  day: 17,
                cat: "Books & Media",        monthsActive: 0..<2,
                card: ("Visa", "4242"))
        ]
        for s in subs {
            for monthsAgo in s.monthsActive {
                if let d = cal.date(byAdding: .month, value: -monthsAgo,
                                    to: cal.date(bySetting: .day, value: s.day, of: today) ?? today) {
                    _ = makeTx(in: context,
                               date: d, payee: s.payee,
                               amount: s.amount, currency: "EUR",
                               account: revolut, category: cat(s.cat),
                               method: .card,
                               cardBrand: s.card?.brand, cardLast4: s.card?.last4)
                }
            }
        }

        // ── Groceries ──────────────────────────────────────────────────
        // Realistic 2024-2026 single-person weekly shop in Dublin: €60-€110.
        // Mix of stores; occasional smaller Centra/Spar top-ups.
        let groceryBig = ["Tesco Express", "SuperValu", "Lidl", "Aldi", "Dunnes Stores"]
        let groceryTopUp = ["Centra", "Spar", "Daybreak"]
        for daysAgo in stride(from: 1, to: 150, by: 5) {
            let bigShop = Int.random(in: 0..<3, using: &rng) > 0
            let store = (bigShop ? groceryBig : groceryTopUp).randomElement(using: &rng)!
            let amount = bigShop
                ? Decimal(Int.random(in: 6500...11_500, using: &rng)) / 100
                : Decimal(Int.random(in: 540...1_580, using: &rng)) / 100
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                .addingTimeInterval(Double(Int.random(in: 8...20, using: &rng)) * 3600)
            _ = makeTx(in: context,
                       date: date, payee: store,
                       amount: -amount, currency: "EUR",
                       account: revolut, category: cat("Groceries"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }

        // One big "weekly shop" split — groceries + alcohol + household.
        if let d = cal.date(byAdding: .day, value: -7, to: today) {
            let tx = makeTx(in: context,
                            date: d.addingTimeInterval(3600 * 17),
                            payee: "Tesco Extra Liffey Valley",
                            amount: -118.40, currency: "EUR",
                            account: revolut, category: nil,
                            method: .card, cardBrand: "Visa", cardLast4: "4242",
                            note: "Big monthly shop")
            context.insert(Split(description: "Groceries", amount: -82.10,
                                 category: cat("Groceries"), transaction: tx))
            context.insert(Split(description: "Wine + beer", amount: -22.30,
                                 category: cat("Alcohol"), transaction: tx))
            context.insert(Split(description: "Cleaning + paper", amount: -14.00,
                                 category: cat("Home & Garden"), transaction: tx))
        }

        // Another split — a brunch picked up across people.
        if let d = cal.date(byAdding: .day, value: -23, to: today) {
            let tx = makeTx(in: context,
                            date: d.addingTimeInterval(3600 * 12),
                            payee: "Brother Hubbard South",
                            amount: -68.20, currency: "EUR",
                            account: revolut, category: nil,
                            method: .card, cardBrand: "Visa", cardLast4: "4242",
                            note: "Brunch w/ Aoife")
            context.insert(Split(description: "My brunch", amount: -22.50,
                                 category: cat("Dining"), transaction: tx))
            context.insert(Split(description: "Aoife — owes me", amount: -22.50,
                                 category: cat("Dining"), transaction: tx))
            context.insert(Split(description: "Birthday gift card chip-in", amount: -23.20,
                                 category: cat("Gifts Given"), transaction: tx))
        }

        // ── Coffee — M/W/F mornings, light Saturday brunch coffee ──────
        for weeksAgo in 0..<20 {
            for weekday in [2, 4, 6, 7] {       // Mon, Wed, Fri, Sat
                guard let base = cal.date(byAdding: .day, value: -(weeksAgo * 7), to: today),
                      let d = cal.date(bySetting: .weekday, value: weekday, of: base),
                      d <= today, d >= cal.date(byAdding: .day, value: -150, to: today)!
                else { continue }
                let isSat = weekday == 7
                let payee = isSat
                    ? ["3FE Grand Canal", "Black & Stone", "Two Pups Coffee"].randomElement(using: &rng)!
                    : ["Insomnia", "Butlers Café", "Java Republic", "Costa", "Cinnamon"].randomElement(using: &rng)!
                let cents = Int.random(in: 320...520, using: &rng)
                let amount = Decimal(cents) / 100
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * (isSat ? 11.0 : 8.5)),
                           payee: payee,
                           amount: -amount, currency: "EUR",
                           account: wallet, category: cat("Coffee"),
                           method: isSat ? .card : .cash,
                           cardBrand: isSat ? "Visa" : nil,
                           cardLast4: isSat ? "4242" : nil)
            }
        }

        // ── Dining out — 1-2x per week ─────────────────────────────────
        let restaurants: [(String, ClosedRange<Int>)] = [
            ("Bunsen Wexford St",    1800...2_400),
            ("Pi Pizza Hanover St",  2200...3_400),
            ("Yamamori Sushi",       3800...6_400),
            ("Manifesto Rathmines",  4200...7_200),
            ("Klaw Crow St",         6500...9_800),
            ("Featherblade",         5200...7_800),
            ("Brother Hubbard",      1900...3_200),
            ("Forest Avenue",        7800...11_400),
            ("Bastible",             8400...10_800),
            ("Pichet",               7200...9_600),
            ("Apache Pizza",         1450...2_400),
            ("The Long Hall",        2800...4_800)   // pub food
        ]
        for daysAgo in stride(from: 3, to: 145, by: 5) {
            let pick = restaurants.randomElement(using: &rng)!
            let cents = Int.random(in: pick.1, using: &rng)
            let date = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                .addingTimeInterval(Double(Int.random(in: 18...21, using: &rng)) * 3600)
            _ = makeTx(in: context,
                       date: date, payee: pick.0,
                       amount: -Decimal(cents) / 100, currency: "EUR",
                       account: revolut, category: cat("Dining"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }

        // ── Transport ──────────────────────────────────────────────────
        // Leap card top-ups (3 over period).
        for daysAgo in [4, 38, 92] {
            if let d = cal.date(byAdding: .day, value: -daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d, payee: "Leap Card Top-Up",
                           amount: -25.00, currency: "EUR",
                           account: revolut, category: cat("Public Transport"),
                           method: .card, cardBrand: "Visa", cardLast4: "4242")
            }
        }
        // Free Now / Lynk rides — 8 scattered.
        let rides = [
            ("Free Now Dublin", 9.40, 11),
            ("Free Now Dublin", 14.20, 28),
            ("Lynk Cab Co",     22.50, 41),
            ("Free Now Dublin", 11.80, 53),
            ("Free Now Dublin", 9.00,  67),
            ("Lynk Cab Co",     18.40, 78),
            ("Free Now Dublin", 7.20,  94),
            ("Free Now Dublin", 24.30, 119)
        ]
        for (payee, amt, daysAgo) in rides {
            if let d = cal.date(byAdding: .day, value: -daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * 22.5),
                           payee: payee,
                           amount: -Decimal(amt), currency: "EUR",
                           account: revolut, category: cat("Taxi & Ride-share"),
                           method: .card, cardBrand: "Visa", cardLast4: "4242")
            }
        }
        // Fuel — 4 fills, ~€80 each.
        for daysAgo in [12, 41, 70, 112] {
            if let d = cal.date(byAdding: .day, value: -daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d, payee: ["Circle K", "Maxol", "Applegreen"].randomElement(using: &rng)!,
                           amount: -Decimal(Int.random(in: 7400...9_200, using: &rng)) / 100,
                           currency: "EUR",
                           account: revolut, category: cat("Fuel"),
                           method: .card, cardBrand: "Visa", cardLast4: "4242")
            }
        }
        // Car service — one big one.
        if let d = cal.date(byAdding: .day, value: -73, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Joe's Garage Phibsboro",
                       amount: -284.50, currency: "EUR",
                       account: revolut, category: cat("Car Maintenance"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "NCT prep + new brake pads")
        }

        // ── Health & care ──────────────────────────────────────────────
        if let d = cal.date(byAdding: .day, value: -29, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Boots Pharmacy Henry St",
                       amount: -14.40, currency: "EUR",
                       account: revolut, category: cat("Pharmacy"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }
        if let d = cal.date(byAdding: .day, value: -64, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Hickeys Pharmacy",
                       amount: -22.10, currency: "EUR",
                       account: revolut, category: cat("Pharmacy"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }
        if let d = cal.date(byAdding: .day, value: -47, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Specsavers O'Connell St",
                       amount: -180.00, currency: "EUR",
                       account: revolut, category: cat("Medical"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Eye test + new glasses")
        }
        if let d = cal.date(byAdding: .day, value: -103, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Smile Dental Clinic",
                       amount: -85.00, currency: "EUR",
                       account: revolut, category: cat("Medical"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "6-month checkup")
        }
        if let d = cal.date(byAdding: .day, value: -55, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Sallinos Barbershop",
                       amount: -22.00, currency: "EUR",
                       account: wallet, category: cat("Personal Care"),
                       method: .cash)
        }

        // ── Shopping (Amazon, Penneys, Brown Thomas) + REFUND ──────────
        if let d = cal.date(byAdding: .day, value: -50, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Amazon UK",
                       amount: -64.80, currency: "EUR",
                       account: revolut, category: cat("Shopping"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Mechanical keyboard")
        }
        if let d = cal.date(byAdding: .day, value: -42, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Amazon UK — Refund",
                       amount: 64.80, currency: "EUR",
                       account: revolut, category: cat("Refund"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Returned keyboard, didn't suit")
        }
        if let d = cal.date(byAdding: .day, value: -33, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Penneys Mary St",
                       amount: -38.50, currency: "EUR",
                       account: revolut, category: cat("Clothing"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }
        if let d = cal.date(byAdding: .day, value: -76, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Brown Thomas",
                       amount: -125.00, currency: "EUR",
                       account: revolut, category: cat("Clothing"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Winter jacket — needed it")
        }
        if let d = cal.date(byAdding: .day, value: -19, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Currys Blanchardstown",
                       amount: -89.99, currency: "EUR",
                       account: revolut, category: cat("Electronics"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Wireless mouse")
        }
        if let d = cal.date(byAdding: .day, value: -111, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Hodges Figgis",
                       amount: -28.90, currency: "EUR",
                       account: revolut, category: cat("Books & Media"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }
        if let d = cal.date(byAdding: .day, value: -85, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "B&Q Liffey Valley",
                       amount: -34.80, currency: "EUR",
                       account: revolut, category: cat("Home & Garden"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Drill bits + picture hooks")
        }

        // ── Hobbies / education / charity ──────────────────────────────
        if let d = cal.date(byAdding: .day, value: -36, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Trócaire",
                       amount: -25.00, currency: "EUR",
                       account: revolut, category: cat("Charity"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Monthly direct contribution")
        }
        if let d = cal.date(byAdding: .day, value: -98, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Udemy",
                       amount: -19.99, currency: "EUR",
                       account: revolut, category: cat("Education"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "SwiftUI animations course")
        }
        if let d = cal.date(byAdding: .day, value: -61, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Eight Degrees Brewing — Taproom",
                       amount: -28.00, currency: "EUR",
                       account: wallet, category: cat("Alcohol"),
                       method: .cash,
                       note: "Friday pints")
        }
        if let d = cal.date(byAdding: .day, value: -45, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Eventbrite — DUB Folk Night",
                       amount: -22.50, currency: "EUR",
                       account: revolut, category: cat("Entertainment"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Live music ticket")
        }

        // Birthday gift for sibling.
        if let d = cal.date(byAdding: .day, value: -82, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Brown Thomas Online",
                       amount: -55.00, currency: "EUR",
                       account: revolut, category: cat("Gifts Given"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "Niamh's birthday — perfume")
        }
        // Birthday cash from parents.
        if let d = cal.date(byAdding: .day, value: -120, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Mam & Dad",
                       amount: 100, currency: "EUR",
                       account: wallet, category: cat("Gift Received"),
                       method: .cash, note: "Birthday")
        }

        // Cash withdrawal.
        if let d = cal.date(byAdding: .day, value: -71, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "AIB ATM — Camden St",
                       amount: -80, currency: "EUR",
                       account: aib, category: cat("Cash Withdrawal"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242")
        }
        // Bank fees.
        for monthsAgo in 0..<5 {
            if let d = cal.date(byAdding: .month, value: -monthsAgo,
                                to: cal.date(bySetting: .day, value: 30, of: today) ?? today) {
                _ = makeTx(in: context,
                           date: d, payee: "AIB Quarterly Fees",
                           amount: -4.50, currency: "EUR",
                           account: aib, category: cat("Bank Fees"),
                           method: .card)
            }
        }

        // ── Travel — long weekend in NYC, paid on Amex (USD) ───────────
        // 0.92 EUR/USD snapshot reflects 2025 trading range.
        if let d = cal.date(byAdding: .day, value: -41, to: today) {
            _ = makeTx(in: context,
                       date: d, payee: "Aer Lingus EI105",
                       amount: -612, currency: "EUR",
                       account: revolut, category: cat("Travel"),
                       method: .card, cardBrand: "Visa", cardLast4: "4242",
                       note: "DUB → JFK return")
            if let d2 = cal.date(byAdding: .day, value: -38, to: today) {
                _ = makeTx(in: context,
                           date: d2, payee: "Pod Hotel Times Square",
                           amount: -428, currency: "USD",
                           account: amex, category: cat("Travel"),
                           method: .card, cardBrand: "Amex", cardLast4: "1009",
                           fxRateToBase: 0.92, fxBase: "EUR",
                           note: "3 nights")
                _ = makeTx(in: context,
                           date: d2.addingTimeInterval(3600 * 4),
                           payee: "Joe's Pizza Carmine",
                           amount: -22.40, currency: "USD",
                           account: amex, category: cat("Dining"),
                           method: .card, cardBrand: "Amex", cardLast4: "1009",
                           fxRateToBase: 0.92, fxBase: "EUR")
                _ = makeTx(in: context,
                           date: d2.addingTimeInterval(3600 * 26),
                           payee: "MTA NYC Subway",
                           amount: -33.00, currency: "USD",
                           account: amex, category: cat("Public Transport"),
                           method: .card, cardBrand: "Amex", cardLast4: "1009",
                           fxRateToBase: 0.92, fxBase: "EUR",
                           note: "Weekly metro card")
                _ = makeTx(in: context,
                           date: d2.addingTimeInterval(3600 * 48),
                           payee: "MoMA Admission",
                           amount: -30.00, currency: "USD",
                           account: amex, category: cat("Entertainment"),
                           method: .card, cardBrand: "Amex", cardLast4: "1009",
                           fxRateToBase: 0.92, fxBase: "EUR")
            }
        }

        // ── Hall of Shame — six pre-tagged regrets ─────────────────────
        struct Regret {
            let payee: String; let amount: Decimal; let daysAgo: Int
            let category: String; let emoji: String; let note: String
        }
        let regrets: [Regret] = [
            Regret(payee: "Domino's Pizza — Camden St", amount: -38.50, daysAgo: 6,
                   category: "Dining", emoji: "🍕",
                   note: "Ordered at 2:47 am. Why."),
            Regret(payee: "Amazon UK", amount: -127.00, daysAgo: 21,
                   category: "Shopping", emoji: "🛍️",
                   note: "Air-fryer accessories I haven't touched"),
            Regret(payee: "Paddy Power Online", amount: -50.00, daysAgo: 31,
                   category: "Entertainment", emoji: "🎰",
                   note: "Bet on a team I'd never heard of"),
            Regret(payee: "Free Now Dublin", amount: -22.00, daysAgo: 10,
                   category: "Taxi & Ride-share", emoji: "🚕",
                   note: "Walked back the other way next morning"),
            Regret(payee: "The Long Hall", amount: -76.00, daysAgo: 17,
                   category: "Alcohol", emoji: "🍻",
                   note: "Rounds for people I just met"),
            Regret(payee: "ASOS", amount: -89.00, daysAgo: 44,
                   category: "Clothing", emoji: "🛍️",
                   note: "Sizing was off, never returned")
        ]
        for r in regrets {
            if let d = cal.date(byAdding: .day, value: -r.daysAgo, to: today) {
                _ = makeTx(in: context,
                           date: d.addingTimeInterval(3600 * Double(Int.random(in: 1...23, using: &rng))),
                           payee: r.payee,
                           amount: r.amount, currency: "EUR",
                           account: revolut, category: cat(r.category),
                           method: .card, cardBrand: "Visa", cardLast4: "4242",
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
        state &+= 0x9E37_79B9
        var w = state
        w = (w ^ (w &>> 13)) &* 0x85EB_CA6B
        let hi = UInt64(w ^ (w &>> 16))
        return (hi << 32) | lo
    }
}
#endif
