import Foundation
import Testing
@testable import HabitTrace

// Nested under `StubbedNetworkSuites` so it never runs alongside other
// stub-backed suites; indentation is kept flat to keep the diff readable.
extension StubbedNetworkSuites {

/// `TaskService.submitOutcome`, the entry point Today uses directly and
/// Plans delegates to. Verifies routing, reconciliation of the shared task
/// array and active map, and that validation happens before the network.
@MainActor
@Suite
struct OutcomeServiceTests {
    private let taskID = "9C3F5A2B-7D4E-4F6A-8B1C-2D3E4F5A6B7C"
    private let executionID = "exec-service-1"

    private var taskListData: Data {
        StubURLProtocol.encode([[
            "id": taskID, "user_id": "user", "title": "HT Test Service",
            "task_category": "Work", "planned_start_time": "9:00 AM",
            "planned_date": TaskTimeFormatting.isoDate(from: .now), "planned_duration_min": 30,
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

    private func finishedData(id: String, status: String, outcome: String) -> Data {
        StubURLProtocol.encode([
            "id": id, "task_id": taskID, "user_id": "user",
            "actual_start_time": "2026-10-11T15:00:00+00:00",
            "actual_end_time": "2026-10-11T15:30:00+00:00",
            "interruption_count": 0, "stopped_early": status == "failed",
            "task_status": status, "failure_reason": NSNull(),
            "outcome_status": outcome, "completion_ratio": status == "success" ? "1" : "0",
            "created_at": "c",
        ])
    }

    /// A service with the task loaded into the shared array and, optionally,
    /// an active execution in the shared map.
    private func makeService(active: Bool) async throws -> TaskService {
        let service = TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession()))
        let tasks = taskListData
        let executions = active ? StubURLProtocol.encode([activeExecutionObject]) : StubURLProtocol.encode([])

        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/tasks"): return .json(200, tasks)
            case ("GET", "/executions"): return .json(200, executions)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }

        await service.loadTasks(accessToken: "token")
        try await service.fetchActiveExecutions(accessToken: "token")
        #expect(service.tasks.count == 1)
        #expect((service.activeExecutions[taskID] != nil) == active)
        return service
    }

    @Test func activeExecutionCompletesAndReconcilesSharedState() async throws {
        let service = try await makeService(active: true)
        let finished = finishedData(id: executionID, status: "success", outcome: "completed")
        let path = "/executions/\(executionID)/complete"
        StubURLProtocol.install { request in
            request.method == "PATCH" && request.path == path ? .json(200, finished) : .detail(500, "unexpected")
        }

        let result = try await service.submitOutcome(accessToken: "token", taskID: taskID, input: OutcomeInput(result: .completed))

        guard case .recorded(let execution) = result else {
            Issue.record("expected recorded"); return
        }
        #expect(execution.id == executionID)
        #expect(service.activeExecutions[taskID] == nil)
        #expect(service.tasks.first?.taskStatus == "success")
        StubURLProtocol.reset()
    }

    @Test func unstartedTaskLogsWithIdempotencyKey() async throws {
        let service = try await makeService(active: false)
        let finished = finishedData(id: "exec-log", status: "failed", outcome: "partial")
        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions" ? .json(201, finished) : .detail(500, "unexpected")
        }

        let input = OutcomeInput(
            result: .partial(percent: 60),
            failureReason: .scheduleOverload,
            interruptionCount: 2,
            actualStart: Date().addingTimeInterval(-3600),
            actualEnd: Date().addingTimeInterval(-120)
        )
        let result = try await service.submitOutcome(accessToken: "token", taskID: taskID, input: input)

        guard case .recorded = result else {
            Issue.record("expected recorded"); return
        }
        let body = try #require(StubURLProtocol.recordedRequests.first?.body)
        #expect(body["idempotency_key"] as? String == taskID)
        #expect(body["completion_ratio"] as? Double == 0.6)
        #expect(body["failure_reason"] as? String == "schedule_overload")
        #expect(service.tasks.first?.taskStatus == "failed")
        StubURLProtocol.reset()
    }

    @Test func stillWorkingStartsWhenNotRunning() async throws {
        let service = try await makeService(active: false)
        let started = StubURLProtocol.encode(activeExecutionObject)
        StubURLProtocol.install { request in
            request.method == "POST" && request.path == "/executions/start" ? .json(201, started) : .detail(500, "unexpected")
        }

        let result = try await service.submitOutcome(accessToken: "token", taskID: taskID, input: OutcomeInput(result: .stillWorking))

        guard case .started(let execution) = result else {
            Issue.record("expected started"); return
        }
        #expect(execution.id == executionID)
        #expect(service.activeExecutions[taskID]?.id == executionID)
        #expect(service.tasks.first?.taskStatus == "pending", "no finished outcome is recorded")
        StubURLProtocol.reset()
    }

    @Test func stillWorkingWhenRunningMakesNoRequest() async throws {
        let service = try await makeService(active: true)
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        let result = try await service.submitOutcome(accessToken: "token", taskID: taskID, input: OutcomeInput(result: .stillWorking))

        #expect(result == .started(service.activeExecutions[taskID]!))
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        StubURLProtocol.reset()
    }

    @Test func invalidInputThrowsBeforeAnyRequest() async throws {
        let service = try await makeService(active: false)
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        await #expect(throws: OutcomeValidationError.missingActualTimes) {
            try await service.submitOutcome(accessToken: "token", taskID: taskID, input: OutcomeInput(result: .completed))
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        #expect(service.tasks.first?.taskStatus == "pending")
        StubURLProtocol.reset()
    }

    @Test func serverFailureLeavesSharedStateUntouched() async throws {
        let service = try await makeService(active: true)
        StubURLProtocol.install { _ in .detail(422, "Specify the actual partial completion_ratio between 0 and 1") }

        await #expect(throws: APIError.self) {
            try await service.submitOutcome(
                accessToken: "token",
                taskID: taskID,
                input: OutcomeInput(result: .abandoned, failureReason: .other)
            )
        }
        #expect(service.activeExecutions[taskID] != nil)
        #expect(service.tasks.first?.taskStatus == "pending")
        StubURLProtocol.reset()
    }
}

}
