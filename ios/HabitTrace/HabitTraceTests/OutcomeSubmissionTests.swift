import Foundation
import Testing
@testable import HabitTrace

// Nested under `StubbedNetworkSuites` so it never runs alongside other
// stub-backed suites; indentation is kept flat to keep the diff readable.
extension StubbedNetworkSuites {

/// `PlansViewModel` → `TaskService` → `APIClient` against a stubbed server.
/// Checks which endpoint each outcome uses, the idempotency key, state
/// reconciliation, failure handling, and duplicate submissions.
@MainActor
@Suite
struct OutcomeSubmissionTests {
    private static let taskID = "7A1D3C2B-4E5F-4A6B-8C9D-0E1F2A3B4C5D"
    private static let executionID = "exec-active-1"

    private let taskID = OutcomeSubmissionTests.taskID
    private let executionID = OutcomeSubmissionTests.executionID
    private let now = Date()

    private var taskListData: Data {
        StubURLProtocol.encode([[
            "id": taskID, "user_id": "user", "title": "HT Test Outcome",
            "task_category": "Work", "planned_start_time": "9:00 AM",
            "planned_date": TaskTimeFormatting.isoDate(from: now), "planned_duration_min": 30,
            "importance": 3, "energy_level": 3, "focus_level": 3,
            "total_tasks_today": 1, "task_status": "pending", "created_at": "c",
        ]])
    }

    private var activeExecutionObject: [String: Any] {
        [
            "id": executionID, "task_id": taskID, "user_id": "user",
            "actual_start_time": "2026-11-09T15:00:00+00:00", "actual_end_time": NSNull(),
            "interruption_count": NSNull(), "stopped_early": false,
            "task_status": NSNull(), "failure_reason": NSNull(), "created_at": "c",
        ]
    }

    private var activeListData: Data { StubURLProtocol.encode([activeExecutionObject]) }
    private let emptyListData = StubURLProtocol.encode([])

    private func finishedExecutionData(id: String, status: String, outcome: String, end: Any = NSNull()) -> Data {
        StubURLProtocol.encode([
            "id": id, "task_id": taskID, "user_id": "user",
            "actual_start_time": NSNull(), "actual_end_time": end,
            "interruption_count": NSNull(), "stopped_early": status == "failed",
            "task_status": status, "failure_reason": NSNull(),
            "outcome_status": outcome, "completion_ratio": status == "success" ? "1.00000" : "0.00000",
            "ai_outcome_sync_status": "pending", "created_at": "c",
        ])
    }

    private func makeLoadedViewModel(active: Bool) async -> (PlansViewModel, TaskService) {
        let service = TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession()))
        let fixedNow = now
        let viewModel = PlansViewModel(taskService: service, accessTokenProvider: { "token" }, now: { fixedNow })

        let tasks = taskListData
        let executions = active ? activeListData : emptyListData
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/tasks"): return .json(200, tasks)
            case ("GET", "/executions"): return .json(200, executions)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }

        await viewModel.load()
        #expect(viewModel.items.count == 1)
        #expect(viewModel.isRunning(taskID) == active)
        return (viewModel, service)
    }

    // MARK: - Existing active execution

    @Test func activeExecutionIsCompletedInPlace() async throws {
        let (viewModel, service) = await makeLoadedViewModel(active: true)
        let finished = finishedExecutionData(id: executionID, status: "success", outcome: "completed")
        let completePath = "/executions/\(executionID)/complete"

        StubURLProtocol.install { request in
            request.method == "PATCH" && request.path == completePath ? .json(200, finished) : .detail(500, "unexpected")
        }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .completed))

        #expect(result?.id == executionID)
        #expect(viewModel.actionErrorMessage == nil)

        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(StubURLProtocol.recordedRequests.count == 1)
        #expect(body["task_status"] as? String == "success")
        #expect(body["actual_end_unknown"] as? Bool == true)
        #expect(body["interruption_count"] is NSNull)
        #expect(body["idempotency_key"] == nil)
        #expect(body["task_id"] == nil)

        #expect(viewModel.isRunning(taskID) == false)
        #expect(service.activeExecutions[taskID] == nil)
        #expect(viewModel.item(for: taskID)?.status == .completed)
        #expect(service.tasks.first { $0.id == taskID }?.taskStatus == "success")
        StubURLProtocol.reset()
    }

    // MARK: - Never started

    @Test func unstartedTaskIsLoggedWithIdempotencyKey() async throws {
        let (viewModel, service) = await makeLoadedViewModel(active: false)
        let finished = finishedExecutionData(id: "exec-new", status: "failed", outcome: "abandoned")

        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions" ? .json(201, finished) : .detail(500, "unexpected")
        }

        let input = OutcomeInput(choice: .notCompleted, minutesSpent: 20, reason: .unexpectedEvent)
        let result = await viewModel.submitOutcome(taskID: taskID, input: input)

        #expect(result?.id == "exec-new")
        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(body["task_id"] as? String == taskID)
        #expect(body["idempotency_key"] as? String == taskID)
        #expect(body["outcome_status"] as? String == "abandoned")
        #expect(body["failure_reason"] as? String == "unexpected_event")
        #expect(body["active_minutes"] as? Int == 20)
        #expect(body["stopped_early"] as? Bool == true)
        #expect(body["actual_end_unknown"] as? Bool == true)

        #expect(viewModel.item(for: taskID)?.status == .notCompleted)
        #expect(service.tasks.first { $0.id == taskID }?.taskStatus == "failed")
        StubURLProtocol.reset()
    }

    @Test func didNotStartLogsNotStartedWithoutTimes() async throws {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        let finished = finishedExecutionData(id: "exec-ns", status: "failed", outcome: "not_started")

        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions" ? .json(201, finished) : .detail(500, "unexpected")
        }

        _ = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .notCompleted, didNotStart: true))

        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(body["outcome_status"] as? String == "not_started")
        #expect(body["actual_start_time"] == nil)
        #expect(body["actual_end_unknown"] == nil)
        #expect(body["interruption_count"] as? Int == 0)
        #expect(viewModel.item(for: taskID)?.status == .notCompleted)
        StubURLProtocol.reset()
    }

    // MARK: - Validation stops before the network

    @Test func invalidInputNeverReachesTheNetwork() async {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput())

        #expect(result == nil)
        #expect(viewModel.actionErrorMessage == OutcomeValidationError.noChoice.errorDescription)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        #expect(viewModel.item(for: taskID)?.status == .pending)
        StubURLProtocol.reset()
    }

    // MARK: - Failures

    @Test func transportFailureLeavesStateUntouched() async {
        let (viewModel, service) = await makeLoadedViewModel(active: true)
        StubURLProtocol.install { _ in throw URLError(.notConnectedToInternet) }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .completed))

        #expect(result == nil)
        #expect(viewModel.actionErrorMessage == "You're offline or the server can't be reached.")
        #expect(viewModel.isRunning(taskID) == true, "active execution must survive a failed write")
        #expect(service.activeExecutions[taskID] != nil)
        #expect(viewModel.item(for: taskID)?.status == .inProgress)
        #expect(viewModel.isBusy == false)
        StubURLProtocol.reset()
    }

    @Test func serverRuleViolationSurfacesDetail() async {
        let (viewModel, _) = await makeLoadedViewModel(active: true)
        StubURLProtocol.install { _ in .detail(422, "An unknown finish time cannot also be provided") }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .completed))

        #expect(result == nil)
        #expect(viewModel.actionErrorMessage == "An unknown finish time cannot also be provided")
        #expect(viewModel.isRunning(taskID) == true)
        StubURLProtocol.reset()
    }

    // MARK: - Duplicate submission

    @Test func concurrentSubmissionsSendOneRequest() async {
        let (viewModel, _) = await makeLoadedViewModel(active: true)
        let finished = finishedExecutionData(id: executionID, status: "success", outcome: "completed")
        StubURLProtocol.install { _ in .json(200, finished) }

        async let first = viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .completed))
        async let second = viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(choice: .completed))
        let results = await [first, second]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(StubURLProtocol.recordedRequests.count == 1)
        StubURLProtocol.reset()
    }

    // MARK: - Logged plan revision

    @Test func loggedPlanEditPatchesTaskThenExecution() async throws {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        let patchedTask = StubURLProtocol.encode([
            "id": taskID, "user_id": "user", "title": "HT Test Outcome 2",
            "task_category": "Work", "planned_start_time": "10:00 AM",
            "planned_date": TaskTimeFormatting.isoDate(from: now), "planned_duration_min": 45,
            "importance": 3, "energy_level": 3, "focus_level": 3,
            "total_tasks_today": 1, "task_status": "failed", "created_at": "c",
        ])
        let revised = finishedExecutionData(id: "exec-f", status: "failed", outcome: "partial")

        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("PATCH", "/tasks/\(Self.taskID)"): return .json(200, patchedTask)
            case ("PATCH", "/executions/exec-f"): return .json(200, revised)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }

        var draft = PlanDraft(task: viewModel.tasks[0])!
        draft.title = "HT Test Outcome 2"
        draft.durationMinutes = 45
        let revision = ExecutionOutcomeRequest(taskStatus: "failed", outcomeStatus: .partial, completionRatio: 0.4, stoppedEarly: true)

        let ok = await viewModel.updateLoggedPlan(taskID: taskID, draft: draft, executionID: "exec-f", revision: revision)

        #expect(ok)
        let paths = StubURLProtocol.recordedRequests.map { "\($0.method) \($0.path)" }
        #expect(paths == ["PATCH /tasks/\(taskID)", "PATCH /executions/exec-f"])
        #expect(viewModel.tasks.first?.title == "HT Test Outcome 2")
        #expect(viewModel.item(for: taskID)?.status == .notCompleted)
        StubURLProtocol.reset()
    }
}

}
