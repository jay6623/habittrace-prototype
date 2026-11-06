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

    // MARK: - Fixtures (pre-encoded so handlers capture only Data)

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
            "actual_start_time": "2026-10-11T15:00:00+00:00", "actual_end_time": NSNull(),
            "interruption_count": 0, "stopped_early": false,
            "task_status": NSNull(), "failure_reason": NSNull(), "created_at": "c",
        ]
    }

    private var activeExecutionData: Data { StubURLProtocol.encode(activeExecutionObject) }
    private var activeListData: Data { StubURLProtocol.encode([activeExecutionObject]) }
    private let emptyListData = StubURLProtocol.encode([])

    private func finishedExecutionData(id: String, status: String, outcome: String) -> Data {
        StubURLProtocol.encode([
            "id": id, "task_id": taskID, "user_id": "user",
            "actual_start_time": "2026-10-11T15:00:00+00:00",
            "actual_end_time": "2026-10-11T15:30:00+00:00",
            "interruption_count": 0, "stopped_early": status == "failed",
            "task_status": status, "failure_reason": NSNull(),
            "outcome_status": outcome, "completion_ratio": status == "success" ? "1.00000" : "0.00000",
            "ai_outcome_sync_status": "pending", "created_at": "c",
        ])
    }

    /// A view model whose day is loaded from the stub, optionally with an
    /// active execution for the task.
    private func makeLoadedViewModel(active: Bool) async -> (PlansViewModel, TaskService) {
        let service = TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession()))
        let fixedNow = now
        let viewModel = PlansViewModel(
            taskService: service,
            accessTokenProvider: { "token" },
            now: { fixedNow }
        )

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
            request.method == "PATCH" && request.path == completePath
                ? .json(200, finished)
                : .detail(500, "unexpected \(request.method) \(request.path)")
        }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .completed))

        #expect(result?.id == executionID)
        #expect(viewModel.actionErrorMessage == nil)

        let writes = StubURLProtocol.recordedRequests
        #expect(writes.count == 1)
        #expect(writes.first?.body?["task_status"] as? String == "success")
        #expect(writes.first?.body?["actual_start_time"] == nil, "complete path sends no times")
        #expect(writes.first?.body?["idempotency_key"] == nil)

        // Reconciliation: active entry cleared, status mirrored to Plans and the shared array.
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
            request.method == "POST" && request.path == "/executions"
                ? .json(201, finished)
                : .detail(500, "unexpected \(request.method) \(request.path)")
        }

        let input = OutcomeInput(
            result: .abandoned,
            failureReason: .unexpectedEvent,
            interruptionCount: 1,
            actualStart: now.addingTimeInterval(-1800),
            actualEnd: now.addingTimeInterval(-60)
        )
        let result = await viewModel.submitOutcome(taskID: taskID, input: input)

        #expect(result?.id == "exec-new")
        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(body["task_id"] as? String == taskID)
        #expect(body["idempotency_key"] as? String == taskID)
        #expect(body["outcome_status"] as? String == "abandoned")
        #expect(body["failure_reason"] as? String == "unexpected_event")
        #expect(body["stopped_early"] as? Bool == true)
        #expect(body["actual_start_time"] is String)
        #expect(body["actual_end_time"] is String)

        #expect(viewModel.item(for: taskID)?.status == .notCompleted)
        #expect(service.tasks.first { $0.id == taskID }?.taskStatus == "failed")
        StubURLProtocol.reset()
    }

    @Test func notStartedOutcomeLogsWithoutTimes() async throws {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        let finished = finishedExecutionData(id: "exec-ns", status: "failed", outcome: "not_started")

        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions"
                ? .json(201, finished)
                : .detail(500, "unexpected")
        }

        _ = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .notStarted))

        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(body["outcome_status"] as? String == "not_started")
        #expect(body["actual_start_time"] == nil)
        #expect(body["interruption_count"] as? Int == 0)
        #expect(viewModel.item(for: taskID)?.status == .notCompleted)
        StubURLProtocol.reset()
    }

    // MARK: - Validation stops before the network

    @Test func invalidInputNeverReachesTheNetwork() async {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        let result = await viewModel.submitOutcome(
            taskID: taskID,
            input: OutcomeInput(result: .partial(percent: 50)) // no reason, no times
        )

        #expect(result == nil)
        #expect(viewModel.actionErrorMessage == OutcomeValidationError.missingFailureReason.errorDescription)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        #expect(viewModel.item(for: taskID)?.status == .pending)
        StubURLProtocol.reset()
    }

    // MARK: - Network failure

    @Test func transportFailureLeavesStateUntouched() async {
        let (viewModel, service) = await makeLoadedViewModel(active: true)
        StubURLProtocol.install { _ in throw URLError(.notConnectedToInternet) }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .completed))

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
        StubURLProtocol.install { _ in .detail(422, "failure_reason is required for a failed execution") }

        let result = await viewModel.submitOutcome(
            taskID: taskID,
            input: OutcomeInput(result: .abandoned, failureReason: .other)
        )

        #expect(result == nil)
        #expect(viewModel.actionErrorMessage == "failure_reason is required for a failed execution")
        #expect(viewModel.isRunning(taskID) == true)
        StubURLProtocol.reset()
    }

    // MARK: - Duplicate submission

    @Test func concurrentSubmissionsSendOneRequest() async {
        let (viewModel, _) = await makeLoadedViewModel(active: true)
        let finished = finishedExecutionData(id: executionID, status: "success", outcome: "completed")
        StubURLProtocol.install { _ in .json(200, finished) }

        async let first = viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .completed))
        async let second = viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .completed))
        let results = await [first, second]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(StubURLProtocol.recordedRequests.count == 1)
        StubURLProtocol.reset()
    }

    // MARK: - Still working

    @Test func stillWorkingStartsAnUnstartedTask() async {
        let (viewModel, _) = await makeLoadedViewModel(active: false)
        let started = activeExecutionData

        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions/start"
                ? .json(201, started)
                : .detail(500, "unexpected")
        }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .stillWorking))

        #expect(result?.id == executionID)
        #expect(viewModel.isRunning(taskID) == true)
        #expect(viewModel.item(for: taskID)?.status == .inProgress)
        StubURLProtocol.reset()
    }

    @Test func stillWorkingOnActiveTaskMakesNoRequest() async {
        let (viewModel, _) = await makeLoadedViewModel(active: true)
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        let result = await viewModel.submitOutcome(taskID: taskID, input: OutcomeInput(result: .stillWorking))

        #expect(result?.id == executionID)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        StubURLProtocol.reset()
    }
}

}
