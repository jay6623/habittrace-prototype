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

/// `GET /analytics/duration-recommendation`: a history-based duration
/// suggestion for a plan, mirroring the PWA's "Suggest from my history".
nonisolated struct DurationRecommendation: Decodable, Equatable, Sendable {
    var available: Bool
    var recommendedMinutes: Int?
    var sampleCount: Int
    /// "same_title", "similar_category", or "insufficient_history".
    var basis: String
    var medianElapsedMinutes: Double?
    var lookbackDays: Int
    var reason: String?

    /// The PWA's explanation under the suggestion, when one is available.
    var explanation: String? {
        guard available, let median = medianElapsedMinutes else { return nil }
        let scope = basis == "same_title"
            ? "with the same name and category"
            : "in this category with a similar planned length"
        return "Based on \(sampleCount) completed plans in the last \(lookbackDays) days \(scope). Median elapsed time: \(Int(median.rounded()))m, including interruptions. Suggested changes are limited to 50%."
    }
}

extension APIClient {
    func fetchDurationRecommendation(
        accessToken: String,
        title: String,
        category: String,
        plannedMinutes: Int,
        excludeTaskID: String?
    ) async throws -> DurationRecommendation {
        var query = [
            URLQueryItem(name: "title", value: title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "planned_minutes", value: String(plannedMinutes)),
        ]
        if let excludeTaskID {
            query.append(URLQueryItem(name: "exclude_task_id", value: excludeTaskID))
        }
        let request = try makeRequest(.get, path: "analytics/duration-recommendation", query: query, accessToken: accessToken)
        return try await send(request)
    }

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
