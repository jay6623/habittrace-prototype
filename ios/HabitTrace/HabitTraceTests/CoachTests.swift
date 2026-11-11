import Foundation
import Testing
@testable import HabitTrace

/// SSE frame parsing and chart validation for the coach.
struct ChatStreamParserTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test func parsesTokensConversationAndDone() throws {
        #expect(try ChatStreamParser.events(fromLine: "data: {\"token\": \"Hel\"}", decoder: decoder) == [.token("Hel")])
        #expect(try ChatStreamParser.events(fromLine: "data: {\"conversation_id\": \"abc\"}", decoder: decoder) == [.conversation(id: "abc")])
        #expect(try ChatStreamParser.events(fromLine: "data: [DONE]", decoder: decoder) == [.done])
        #expect(try ChatStreamParser.events(fromLine: "", decoder: decoder).isEmpty)
        #expect(try ChatStreamParser.events(fromLine: "event: ping", decoder: decoder).isEmpty)
        #expect(try ChatStreamParser.events(fromLine: "data: not json", decoder: decoder).isEmpty)
    }

    @Test func errorFrameThrows() {
        #expect(throws: ChatStreamError(message: "Rate limited")) {
            try ChatStreamParser.events(fromLine: "data: {\"error\": \"Rate limited\"}", decoder: decoder)
        }
    }

    @Test func parsesTaskAndScheduleProposals() throws {
        let task = """
        data: {"proposal": {"id": "p1", "task": {"title": "Gym", "task_category": "Exercise", "planned_start_time": "18:00", "planned_date": "2026-11-10", "planned_duration_min": 45, "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1}, "options": [{"start": "2026-11-10T18:00:00+00:00", "end": "2026-11-10T18:45:00+00:00", "score": 0.82, "reasons": ["Evenings work for you"]}]}}
        """
        let events = try ChatStreamParser.events(fromLine: task, decoder: decoder)
        guard case .proposal(.task(let proposal)) = events.first else {
            Issue.record("expected task proposal"); return
        }
        #expect(proposal.id == "p1")
        #expect(proposal.task.title == "Gym")
        #expect(proposal.options.first?.score == 0.82)

        let schedule = """
        data: {"proposal": {"kind": "daily_schedule", "schedule": {"id": "s1", "selected_date": "2026-11-10", "timezone_name": "UTC", "status": "draft", "scheduled_tasks": [{"task_id": "t1", "title": "Report", "estimated_duration_minutes": 60, "category": "Work", "scheduled_start": "2026-11-10T09:00:00+00:00", "scheduled_end": "2026-11-10T10:00:00+00:00", "predicted_success_probability": 0.7}], "unscheduled_tasks": [], "warnings": []}}}
        """
        guard case .proposal(.dailySchedule(let draft)) = try ChatStreamParser.events(fromLine: schedule, decoder: decoder).first else {
            Issue.record("expected schedule proposal"); return
        }
        #expect(draft.id == "s1")
        #expect(draft.scheduledTasks.count == 1)
    }

    @Test func chartsMustBeInternallyConsistent() throws {
        let valid = """
        data: {"chart": {"chart_type": "bar", "title": "Completion by hour", "x_axis": "Hour", "y_axis": "Rate", "units": "percent", "period": {"start": "2026-10-01", "end": "2026-10-31"}, "sample_size": 10, "note": "n", "data": [{"label": "9 AM", "value": 50.0, "sample_size": 4, "completed": 2}, {"label": "2 PM", "value": 100.0, "sample_size": 6, "completed": 6}]}}
        """
        guard case .chart(let chart) = try ChatStreamParser.events(fromLine: valid, decoder: decoder).first else {
            Issue.record("expected chart"); return
        }
        #expect(chart.isValid)

        let inconsistent = valid.replacingOccurrences(of: "\"sample_size\": 10", with: "\"sample_size\": 11")
        #expect(try ChatStreamParser.events(fromLine: inconsistent, decoder: decoder).isEmpty)
    }

    @Test func comparisonLinesDisplayAsBars() {
        let spec = CoachChartSpec(
            chartType: "line", title: "Trend", xAxis: "Period", yAxis: "Rate", units: "percent",
            period: .init(start: "2026-09-01", end: "2026-10-31"), sampleSize: 12, intervalDays: nil, focus: nil, note: "n",
            data: [
                .init(label: "2026-09-01 – 2026-09-30", value: 50, sampleSize: 6, completed: 3),
                .init(label: "2026-10-01 – 2026-10-31", value: 66.7, sampleSize: 6, completed: 4),
            ]
        )
        let display = spec.forDisplay
        #expect(display.chartType == "bar")
        #expect(display.focus == "comparison")
        #expect(display.title == "Completion rate by period")
    }

    @Test func lineSeriesLeavesGapsForMissingDays() {
        let spec = CoachChartSpec(
            chartType: "line", title: "Daily", xAxis: "Day", yAxis: "Rate", units: "percent",
            period: .init(start: "2026-11-01", end: "2026-11-04"), sampleSize: 6, intervalDays: 1, focus: nil, note: "n",
            data: [
                .init(label: "2026-11-01", value: 100, sampleSize: 2, completed: 2),
                .init(label: "2026-11-03", value: 50, sampleSize: 2, completed: 1),
                .init(label: "2026-11-04", value: 0, sampleSize: 2, completed: 0),
            ]
        )
        let series = CoachChartView.series(for: spec)
        #expect(series.map(\.label) == ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"])
        #expect(series[1].value == nil)
        #expect(series[0].run != series[2].run, "a gap must start a new line run")
        #expect(series[2].run == series[3].run)
    }

    @Test func timeParsingAcceptsBothClockFormats() {
        #expect(TaskConfirmCard.minutes(from: "18:30") == 18 * 60 + 30)
        #expect(TaskConfirmCard.minutes(from: "6:30 PM") == 18 * 60 + 30)
        #expect(TaskConfirmCard.minutes(from: "12:05 AM") == 5)
        #expect(TaskConfirmCard.minutes(from: "nope") == nil)
    }
}

extension StubbedNetworkSuites {

/// Streaming through `APIClient` and the view model's conversation state.
@MainActor
@Suite
struct CoachViewModelTests {
    private func makeViewModel(taskService: TaskService? = nil) -> CoachViewModel {
        CoachViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), taskService: taskService, accessTokenProvider: { "token" })
    }

    private let streamBody = Data("""
    data: {"conversation_id": "conv-1"}

    data: {"token": "Plan "}

    data: {"token": "your day."}

    data: {"proposal": {"id": "p1", "task": {"title": "Gym", "task_category": "Exercise", "planned_start_time": "18:00", "planned_date": "2026-11-10", "planned_duration_min": 45, "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1}, "options": []}}

    data: [DONE]

    """.utf8)

    @Test func sendStreamsTokensAndKeepsProposal() async throws {
        let body = streamBody
        StubURLProtocol.install { request in
            request.path == "/chat/conversations/latest" ? .json(200, Data("null".utf8)) : .json(200, body)
        }
        let viewModel = makeViewModel()
        await viewModel.loadHistory()
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.showsWelcome)

        await viewModel.send("Plan my day")

        #expect(viewModel.conversationID == "conv-1")
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[1].content == "Plan your day.")
        #expect(viewModel.messages[1].proposalStatus == .pending)
        #expect(viewModel.isStreaming == false)
        #expect(viewModel.errorMessage == nil)

        let chat = try #require(StubURLProtocol.recordedRequests.first { $0.path == "/chat" })
        let sent = try #require(chat.body)
        #expect(sent["message"] as? String == "Plan my day")
        #expect((sent["history"] as? [[String: Any]])?.isEmpty == true)
        // Omitted or explicit null both decode as `None` on the backend.
        #expect(sent["conversation_id"] == nil || sent["conversation_id"] is NSNull)
        #expect(sent["timezone_name"] as? String == TimeZone.current.identifier)
        StubURLProtocol.reset()
    }

    @Test func streamErrorFrameSurfacesMessage() async {
        let body = Data("data: {\"token\": \"Hi\"}\n\ndata: {\"error\": \"Model offline\"}\n\n".utf8)
        StubURLProtocol.install { _ in .json(200, body) }
        let viewModel = makeViewModel()

        await viewModel.send("Hello")

        #expect(viewModel.errorMessage == "Model offline")
        #expect(viewModel.messages.count == 1, "no assistant bubble is added for a failed stream")
        StubURLProtocol.reset()
    }

    @Test func httpFailureUsesBackendDetail() async {
        StubURLProtocol.install { _ in .detail(429, "Too many coach requests. Try again in a minute.") }
        let viewModel = makeViewModel()

        await viewModel.send("Hello")

        #expect(viewModel.errorMessage == "Too many coach requests. Try again in a minute.")
        StubURLProtocol.reset()
    }

    @Test func confirmingProposalAddsTaskAndMessage() async throws {
        let service = TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession()))
        let created = StubURLProtocol.encode([
            "id": "11111111-2222-4333-8444-555555555555", "user_id": "user", "title": "Gym",
            "task_category": "Exercise", "planned_start_time": "6:00 PM",
            "planned_date": "2026-11-10", "planned_duration_min": 45,
            "importance": 3, "energy_level": 3, "focus_level": 3,
            "total_tasks_today": 1, "task_status": "pending", "created_at": "c",
        ])
        let body = streamBody
        StubURLProtocol.install { request in
            switch request.path {
            case "/chat": return .json(200, body)
            case "/chat/proposals/p1/confirm": return .json(200, created)
            default: return .detail(500, "unexpected \(request.path)")
            }
        }
        let viewModel = makeViewModel(taskService: service)
        await viewModel.send("Plan my day")
        let message = try #require(viewModel.messages.last)
        guard case .task(let proposal)? = message.proposal else { Issue.record("expected proposal"); return }

        var draft = proposal.task
        draft.title = "Gym session"
        await viewModel.confirmTask(messageID: message.id, proposal: proposal, candidateStart: nil, draft: draft)

        let confirm = try #require(StubURLProtocol.recordedRequests.first { $0.path == "/chat/proposals/p1/confirm" })
        let sent = try #require(confirm.body)
        #expect((sent["task"] as? [String: Any])?["title"] as? String == "Gym session")
        #expect(sent["candidate_start"] == nil || sent["candidate_start"] is NSNull)
        #expect(viewModel.messages[1].proposalStatus == .confirmed)
        #expect(viewModel.messages.last?.content.contains("has been added to your schedule") == true)
        #expect(service.tasks.contains { $0.title == "Gym" })
        StubURLProtocol.reset()
    }

    @Test func historyRestoresMessagesAndPendingProposals() async {
        let conversation = StubURLProtocol.encode([
            "id": "conv-9",
            "messages": [
                ["id": "m1", "role": "user", "content": "Hi", "created_at": "c"],
                ["id": "m2", "role": "assistant", "content": "Hello", "created_at": "c", "metadata": ["chart": NSNull()]],
            ],
            "pending_proposals": [
                ["id": "p2", "task": ["title": "Read", "task_category": "Study", "planned_start_time": "20:00", "planned_duration_min": 30, "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1], "options": []],
            ],
        ])
        StubURLProtocol.install { _ in .json(200, conversation) }
        let viewModel = makeViewModel()

        await viewModel.loadHistory()

        #expect(viewModel.conversationID == "conv-9")
        #expect(viewModel.messages.count == 3)
        #expect(viewModel.messages[2].content == "This recommendation is still waiting for your confirmation.")
        #expect(viewModel.messages[2].proposalStatus == .pending)
        StubURLProtocol.reset()
    }

    @Test func clearArchivesAndResets() async throws {
        let conversation = StubURLProtocol.encode(["id": "conv-9", "messages": [["id": "m1", "role": "user", "content": "Hi"]], "pending_proposals": []])
        StubURLProtocol.install { request in
            request.method == "DELETE" ? .json(204, Data()) : .json(200, conversation)
        }
        let viewModel = makeViewModel()
        await viewModel.loadHistory()
        #expect(viewModel.messages.count == 1)

        await viewModel.clearConversation()

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.conversationID == nil)
        let archive = try #require(StubURLProtocol.recordedRequests.first { $0.method == "DELETE" })
        #expect(archive.path == "/chat/conversations/conv-9")
        StubURLProtocol.reset()
    }
}

}
