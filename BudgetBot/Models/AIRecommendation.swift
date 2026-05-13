import Foundation
import SwiftData

enum RecommendationKind: String, Codable {
    case silly
    case savings
    case general
}

@Model
final class AIRecommendation {
    var id: UUID = UUID()
    var kindRaw: String = RecommendationKind.general.rawValue
    var title: String = ""
    var body: String = ""
    var estimatedMonthlySavings: Decimal?
    var dismissed: Bool = false
    var createdAt: Date = Date.now

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
