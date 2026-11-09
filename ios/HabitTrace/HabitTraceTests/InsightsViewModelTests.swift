import Foundation
import Testing
@testable import HabitTrace

extension StubbedNetworkSuites {

/// Analytics loading, period switching, and derived display values.
@MainActor
@Suite
struct InsightsViewModelTests {
    private func summaryData(totalTasks: Int = 12) -> Data {
        StubURLProtocol.encode([
            "period": "week", "total_tasks": totalTasks, "success_rate": 66.7,
            "total_planned_minutes": 540, "avg_importance": 3.2, "avg_interruptions": NSNull(),
            "most_failed_category": "Study", "best_time_of_day": "9-12 PM",
            "failure_by_category": ["Study": 3, "Work": 1],
            "failure_by_reason": ["schedule_overload": 2, "low_readiness": 1, "other": 1],
            "execution_trend": [
                ["label": "Mon", "planned_mins": 60, "completed_mins": 30, "success_rate": 50],
                ["label": "Tue", "planned_mins": 90, "completed_mins": 90, "success_rate": 100],
            ],
            "success_by_hour": ["6-9 AM": 80, "9-12 PM": 90.5, "12-3 PM": 40, "3-6 PM": 60, "6-9 PM": 20, "9-12 AM": 0],
        ])
    }

    private let personalizedData = StubURLProtocol.encode([
        "available": true, "reason": NSNull(), "period": "week", "sample_count": 9,
        "confidence_label": "early", "success_rate": 66.7, "previous_success_rate": 50,
        "change_percentage_points": 16.7,
        "strongest_pattern": ["type": "category", "label": "Work", "direction": "positive", "sample_count": 4,
                              "success_rate": 100, "difference": 33.3, "message": "Work plans finish most often."],
        "pattern_to_watch": NSNull(),
        "recommended_experiment": ["title": "Shorter study blocks", "detail": "Try 25 minutes."],
    ])

    @Test func loadsSummaryAndPersonalizedTogether() async throws {
        let summary = summaryData()
        let personalized = personalizedData
        StubURLProtocol.install { request in
            switch request.path {
            case "/analytics/summary": return .json(200, summary)
            case "/analytics/personalized-insights": return .json(200, personalized)
            default: return .detail(500, "unexpected \(request.path)")
            }
        }
        let viewModel = InsightsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessTokenProvider: { "token" })

        await viewModel.load()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.summary?.totalTasks == 12)
        #expect(viewModel.personalized?.strongestPattern?.message == "Work plans finish most often.")
        #expect(viewModel.personalized?.recommendedExperiment.title == "Shorter study blocks")

        let paths = StubURLProtocol.recordedRequests.map(\.path).sorted()
        #expect(paths == ["/analytics/personalized-insights", "/analytics/summary"])
        let summaryRequest = try #require(StubURLProtocol.recordedRequests.first { $0.path == "/analytics/summary" })
        #expect(summaryRequest.queryParameters["period"] == "week")
        StubURLProtocol.reset()
    }

    @Test func personalizedFailureKeepsSummary() async {
        let summary = summaryData()
        StubURLProtocol.install { request in
            request.path == "/analytics/summary" ? .json(200, summary) : .detail(503, "unavailable")
        }
        let viewModel = InsightsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessTokenProvider: { "token" })

        await viewModel.load()

        #expect(viewModel.summary != nil)
        #expect(viewModel.personalized == nil)
        #expect(viewModel.errorMessage == nil)
        StubURLProtocol.reset()
    }

    @Test func summaryFailureShowsPWAMessage() async {
        StubURLProtocol.install { _ in .detail(500, "boom") }
        let viewModel = InsightsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessTokenProvider: { "token" })

        await viewModel.load()

        #expect(viewModel.summary == nil)
        #expect(viewModel.errorMessage == "We couldn’t load your insights. Please try again.")
        #expect(viewModel.isLoading == false)
        StubURLProtocol.reset()
    }

    @Test func derivedValuesFollowThePWA() async {
        let summary = summaryData()
        let personalized = personalizedData
        StubURLProtocol.install { request in
            request.path == "/analytics/summary" ? .json(200, summary) : .json(200, personalized)
        }
        let viewModel = InsightsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessTokenProvider: { "token" })
        await viewModel.load()

        #expect(viewModel.stats.map(\.value) == ["66.7%", "12", "Study", "9-12 PM", "—", "3.2"])
        #expect(viewModel.stats[1].caption == "in this week")
        #expect(viewModel.hourBuckets.map(\.label) == ["6-9 AM", "9-12 PM", "12-3 PM", "3-6 PM", "6-9 PM", "9-12 AM"])
        #expect(viewModel.failureCategories.map(\.label) == ["Study", "Work"])
        #expect(viewModel.failureReasons.map(\.label) == ["Schedule Overload", "Low Readiness", "Other"])
        #expect(viewModel.keyInsights.map(\.title) == ["Best: 9-12 PM", "Most failures: Study", "Success rate: 66.7%"])
        #expect(viewModel.keyInsights[0].detail == "90.5% success rate")
        StubURLProtocol.reset()
    }

    @Test func changingPeriodReloadsWithNewQuery() async throws {
        let summary = summaryData(totalTasks: 0)
        StubURLProtocol.install { request in
            request.path == "/analytics/summary" ? .json(200, summary) : .detail(503, "no")
        }
        let viewModel = InsightsViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessTokenProvider: { "token" })
        await viewModel.load()
        #expect(viewModel.isEmpty)

        viewModel.period = .threeMonths
        try await Task.sleep(for: .milliseconds(300))

        let periods = StubURLProtocol.recordedRequests.filter { $0.path == "/analytics/summary" }.compactMap { $0.queryParameters["period"] }
        #expect(periods == ["week", "3months"])
        StubURLProtocol.reset()
    }
}

}
