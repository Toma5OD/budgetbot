import Foundation

/// One line of sass for the daily roast.
struct RoastLine: Hashable {
    enum Tone { case roast, praise, neutral }
    let text: String
    let tone: Tone
}

/// Generates a daily "harsh-jokey" review of the user's recent spend
/// and save behaviour. Pure logic — feed it snapshots, get back at
/// most three lines.
///
/// Variation across days comes from a date-indexed pick across each
/// rule's phrasings, so the same data produces stable-but-not-
/// repetitive copy. Re-running on the same day yields the same lines —
/// the roast is supposed to feel like a verdict, not a slot machine.
enum DailyRoast {

    // MARK: - Snapshots (kept off SwiftData so this is testable)

    struct TxSnapshot {
        let payee: String
        let amount: Decimal
        let date: Date
        let categoryName: String?
    }

    struct GoalSnapshot {
        let isHit: Bool
        let pace: SavingsGoal.Pace
        let completedAt: Date?
    }

    struct Input {
        let now: Date
        /// Last 7 days, expenses *and* income.
        let recentTransactions: [TxSnapshot]
        let activeGoals: [GoalSnapshot]
        let subscriptionCount: Int
    }

    // MARK: - Generation

    static func generate(input: Input) -> [RoastLine] {
        var hits: [(priority: Int, line: RoastLine)] = []
        if let h = goalHitTodayRule(input)  { hits.append(h) }
        if let h = takeawayRule(input)      { hits.append(h) }
        if let h = coffeeRule(input)        { hits.append(h) }
        if let h = bigSpendRule(input)      { hits.append(h) }
        if let h = subscriptionRule(input)  { hits.append(h) }
        if let h = savingsRule(input)       { hits.append(h) }
        if let h = quietDayRule(input)      { hits.append(h) }

        if hits.isEmpty {
            return [RoastLine(
                text: "Nothing weird in the last day. Suspicious.",
                tone: .neutral
            )]
        }
        return Array(hits
            .sorted { $0.priority > $1.priority }
            .prefix(3)
            .map(\.line))
    }

    // MARK: - Rules

    private static func coffeeRule(_ input: Input) -> (priority: Int, line: RoastLine)? {
        let count = input.recentTransactions
            .filter { MerchantClassifier.isCoffee($0.payee) }
            .count
        guard count >= 3 else { return nil }
        let lines = [
            "\(count) coffees this week. genius.",
            "wow, another \(count)-coffee week. personality.",
            "\(count) lattes you're convinced you needed. okay.",
            "your caffeine receipts (\(count)) are basically a CV now."
        ]
        return (6, RoastLine(text: pick(lines, on: input.now), tone: .roast))
    }

    private static func takeawayRule(_ input: Input) -> (Int, RoastLine)? {
        let cal = Calendar.current
        let dayAgo = cal.date(byAdding: .day, value: -1, to: input.now) ?? input.now
        let recent = input.recentTransactions
            .filter { $0.date > dayAgo }
            .filter { MerchantClassifier.isFastFood($0.payee) }
        guard !recent.isEmpty else { return nil }
        let lines = [
            "yes, the takeaway last night was a great idea. genius.",
            "another fast-food run. the gym membership says hi.",
            "ordering in again. cooking is a myth, sure.",
            "that takeaway charge is screaming for a redo."
        ]
        return (7, RoastLine(text: pick(lines, on: input.now), tone: .roast))
    }

    private static func bigSpendRule(_ input: Input) -> (Int, RoastLine)? {
        // Biggest single expense in the week, ignoring rent-shaped fixed bills.
        let bigs = input.recentTransactions
            .filter { $0.amount < 0 }
            .filter {
                NSDecimalNumber(decimal: -$0.amount).doubleValue >= 100
            }
            .filter { ($0.categoryName ?? "").lowercased() != "rent" }
            .sorted { $0.amount < $1.amount }
        guard let big = bigs.first else { return nil }
        let amount = NSDecimalNumber(decimal: -big.amount).doubleValue
        let roundedEuros = Int(amount.rounded())
        let lines = [
            "€\(roundedEuros) at \(big.payee). must be nice.",
            "€\(roundedEuros) one-shot at \(big.payee). impulse or hostage situation?",
            "you dropped €\(roundedEuros) at \(big.payee). I'm sure you'll use it.",
            "\(big.payee) charged you €\(roundedEuros). hope it was worth it."
        ]
        return (5, RoastLine(text: pick(lines, on: input.now), tone: .roast))
    }

    private static func subscriptionRule(_ input: Input) -> (Int, RoastLine)? {
        guard input.subscriptionCount >= 5 else { return nil }
        let n = input.subscriptionCount
        let lines = [
            "\(n) active subscriptions. quitting a few might be your love language.",
            "still on \(n) subscriptions. is one of them actually getting used?",
            "\(n) recurring charges. somewhere a CFO weeps.",
            "you have \(n) subs. brave."
        ]
        return (4, RoastLine(text: pick(lines, on: input.now), tone: .roast))
    }

    private static func savingsRule(_ input: Input) -> (Int, RoastLine)? {
        let onTrack = input.activeGoals.contains {
            $0.pace == .ahead || $0.pace == .onTrack
        }
        guard onTrack else { return nil }
        let lines = [
            "your saving is on track. I guess that's alright.",
            "you're ahead of pace. don't get cocky.",
            "the numbers say you're winning. weird flex.",
            "saving like a responsible person. who hurt you."
        ]
        return (3, RoastLine(text: pick(lines, on: input.now), tone: .praise))
    }

    private static func quietDayRule(_ input: Input) -> (Int, RoastLine)? {
        let cal = Calendar.current
        let yesterday = cal.startOfDay(
            for: cal.date(byAdding: .day, value: -1, to: input.now) ?? input.now
        )
        let dayLater = cal.date(byAdding: .day, value: 1, to: yesterday) ?? yesterday
        let any = input.recentTransactions.contains {
            $0.date >= yesterday && $0.date < dayLater
        }
        guard !any else { return nil }
        let lines = [
            "zero spends yesterday. fiscal monk behaviour. unrecognisable.",
            "no transactions yesterday. very mature.",
            "you spent nothing yesterday. surely impossible.",
            "you broke even with the void yesterday. proud-ish."
        ]
        return (2, RoastLine(text: pick(lines, on: input.now), tone: .neutral))
    }

    private static func goalHitTodayRule(_ input: Input) -> (Int, RoastLine)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: input.now)
        let hit = input.activeGoals.contains { g in
            guard let completed = g.completedAt else {
                return g.isHit  // newly hit but not manually marked yet
            }
            return cal.startOfDay(for: completed) == today
        }
        guard hit else { return nil }
        let lines = [
            "you hit a goal. fine. proud, I guess.",
            "goal completed. don't make a whole thing of it.",
            "the math says you actually did it. uncanny.",
            "you did the saving. now go claim that reward, big shot."
        ]
        return (10, RoastLine(text: pick(lines, on: input.now), tone: .praise))
    }

    // MARK: - Helpers

    /// Deterministic per-day choice across `options`. Same date → same
    /// pick (no slot-machine mid-day shuffling), next day rotates.
    private static func pick<T>(_ options: [T], on date: Date) -> T {
        precondition(!options.isEmpty)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return options[day % options.count]
    }
}
