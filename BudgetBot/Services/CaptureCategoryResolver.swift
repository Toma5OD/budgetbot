import Foundation
import SwiftData

/// Maps an `ExtractedDraft.suggestedCategory` / `newCategory` to an actual
/// `TxCategory` row, creating one if the AI proposed something genuinely
/// new and we can't fuzzy-match it. Both YOLO commit and the swipe review
/// route through here so behaviour is identical.
enum CaptureCategoryResolver {

    /// `categories` is passed inout so newly created rows show up for
    /// subsequent drafts in the same batch — avoids inserting "Vape Shop"
    /// twice when two receipts in one batch share that category.
    static func resolve(
        draft: ExtractedDraft,
        in categories: inout [TxCategory],
        context: ModelContext
    ) -> TxCategory? {
        let kind: CategoryKind = draft.amount >= 0 ? .income : .expense

        // 1) Exact + fuzzy match on AI's suggested_category (the controlled list).
        if let suggested = draft.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggested.isEmpty {
            if let match = match(name: suggested, in: categories) { return match }
        }

        // 2) AI proposed a brand-new category — match before creating.
        if let proposed = draft.newCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proposed.isEmpty {
            if let match = match(name: proposed, in: categories) { return match }
            // No match: create it.
            let new = TxCategory(
                name: Self.titleCase(proposed),
                kind: kind,
                emoji: "🏷️"
            )
            context.insert(new)
            categories.append(new)
            return new
        }

        // 3) Nothing usable from AI — leave uncategorised so the user can fix.
        return nil
    }

    /// Strict + fuzzy match against existing names.
    private static func match(name: String, in categories: [TxCategory]) -> TxCategory? {
        let needle = name.lowercased()
        if let exact = categories.first(where: { $0.name.lowercased() == needle }) {
            return exact
        }
        // Substring tolerance: "Pharmacy & Drugs" against existing "Pharmacy"
        if let contains = categories.first(where: {
            let n = $0.name.lowercased()
            return n.hasPrefix(needle) || needle.hasPrefix(n)
                || n.contains(needle) || needle.contains(n)
        }) {
            return contains
        }
        // Plural / singular tolerance via tiny stem ("Pharmacies" → "Pharmacy")
        let needleStem = stem(needle)
        if let stemmed = categories.first(where: { stem($0.name.lowercased()) == needleStem }) {
            return stemmed
        }
        return nil
    }

    /// Strip the common English plural endings so "Pharmacies"/"Pharmacy"
    /// converge to the same root. Order matters: longer suffixes first.
    /// Both forms stem to "pharmac".
    private static func stem(_ s: String) -> String {
        for suffix in ["ies", "es", "s", "y"] {
            if s.hasSuffix(suffix), s.count > suffix.count + 2 {
                return String(s.dropLast(suffix.count))
            }
        }
        return s
    }

    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
