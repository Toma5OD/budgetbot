import Foundation
import SwiftData

enum RecommendationKind: String, Codable {
    case silly       // questionable / wasteful spending
    case savings     // savings opportunities
    case general     // general advice
}

@Model
final class AIRecommendation {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var body: String
    var estimatedMonthlySavings: Decimal?
    var dismissed: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: RecommendationKind,
        title: String,
        body: String,
        estimatedMonthlySavings: Decimal? = nil,
        dismissed: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.estimatedMonthlySavings = estimatedMonthlySavings
        self.dismissed = dismissed
        self.createdAt = createdAt
    }

    var kind: RecommendationKind {
        get { RecommendationKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }
}
