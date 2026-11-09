import Foundation

/// Reporting window shared by `/analytics/summary` and
/// `/analytics/personalized-insights`.
nonisolated enum InsightsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case threeMonths = "3months"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 months"
        }
    }

    /// Lower-case noun used in copy such as "in this week".
    var noun: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .threeMonths: "3 months"
        }
    }

    /// "What AI learned from this {…}".
    var learnedFromText: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .threeMonths: "3-month period"
        }
    }
}

nonisolated struct TrendPoint: Decodable, Equatable, Sendable {
    var label: String
    var plannedMins: Int
    var completedMins: Int
    var successRate: Double
}

/// `GET /analytics/summary`.
nonisolated struct AnalyticsSummary: Decodable, Equatable, Sendable {
    var period: String
    var totalTasks: Int
    var successRate: Double
    var totalPlannedMinutes: Int
    var avgImportance: Double
    var avgInterruptions: Double?
    var mostFailedCategory: String
    var bestTimeOfDay: String
    var failureByCategory: [String: Int]
    var failureByReason: [String: Int]
    var executionTrend: [TrendPoint]
    var successByHour: [String: Double]
}

nonisolated struct PersonalizedPattern: Decodable, Equatable, Sendable {
    var type: String
    var label: String
    var direction: String
    var sampleCount: Int
    var successRate: Double
    var difference: Double
    var message: String
}

nonisolated struct RecommendedExperiment: Decodable, Equatable, Sendable {
    var title: String
    var detail: String
}

/// `GET /analytics/personalized-insights`.
nonisolated struct PersonalizedInsights: Decodable, Equatable, Sendable {
    var available: Bool
    var reason: String?
    var period: String
    var sampleCount: Int
    var confidenceLabel: String
    var successRate: Double?
    var previousSuccessRate: Double?
    var changePercentagePoints: Double?
    var strongestPattern: PersonalizedPattern?
    var patternToWatch: PersonalizedPattern?
    var recommendedExperiment: RecommendedExperiment
}

extension APIClient {
    func fetchAnalyticsSummary(accessToken: String, period: InsightsPeriod) async throws -> AnalyticsSummary {
        let request = try makeRequest(
            .get,
            path: "analytics/summary",
            query: [URLQueryItem(name: "period", value: period.rawValue)],
            accessToken: accessToken
        )
        return try await send(request)
    }

    func fetchPersonalizedInsights(
        accessToken: String,
        period: InsightsPeriod,
        endDate: String
    ) async throws -> PersonalizedInsights {
        let request = try makeRequest(
            .get,
            path: "analytics/personalized-insights",
            query: [
                URLQueryItem(name: "period", value: period.rawValue),
                URLQueryItem(name: "end_date", value: endDate),
            ],
            accessToken: accessToken
        )
        return try await send(request)
    }
}
