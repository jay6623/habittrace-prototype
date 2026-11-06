import Foundation
import Testing
@testable import HabitTrace

/// Pure validation and request construction, no network.
struct OutcomeRequestBuilderTests {
    private let taskID = "6D2C0F0E-1F6B-4C7D-9A3E-2B1C4D5E6F70"
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private var start: Date { now.addingTimeInterval(-3600) }
    private var end: Date { now.addingTimeInterval(-600) }

    private var active: HabitTraceExecution {
        HabitTraceExecution(
            id: "exec-1",
            taskId: taskID,
            userId: "user",
            actualStartTime: "2026-10-11T15:00:00+00:00",
            actualEndTime: nil,
            interruptionCount: 0,
            stoppedEarly: false,
            taskStatus: nil,
            failureReason: nil,
            createdAt: "c"
        )
    }

    private func build(_ input: OutcomeInput, active: HabitTraceExecution? = nil) throws -> OutcomeSubmission {
        try OutcomeRequestBuilder.build(input, taskID: taskID, activeExecution: active, now: now)
    }

    private func request(from submission: OutcomeSubmission) -> ExecutionOutcomeRequest? {
        switch submission {
        case .keepActive: nil
        case .completeActive(_, let request): request
        case .log(_, _, let request): request
        }
    }

    // MARK: - Each outcome type

    @Test func completedWithTimesLogsSuccess() throws {
        let submission = try build(OutcomeInput(result: .completed, interruptionCount: 2, actualStart: start, actualEnd: end))
        guard case .log(let id, let key, let request) = submission else {
            Issue.record("expected log"); return
        }
        #expect(id == taskID)
        #expect(key == taskID)
        #expect(request.taskStatus == "success")
        #expect(request.outcomeStatus == .completed)
        #expect(request.completionRatio == 1)
        #expect(request.stoppedEarly == false)
        #expect(request.failureReason == nil)
        #expect(request.interruptionCount == 2)
        #expect(request.actualStartTime == start)
        #expect(request.actualEndTime == end)
    }

    @Test func completedIgnoresProvidedReason() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .completed, failureReason: .interruption, actualStart: start, actualEnd: end)
        )))
        #expect(request.failureReason == nil)
    }

    @Test func partialMapsPercentToRatioAndStopsEarly() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .partial(percent: 40), failureReason: .underestimatedTime, interruptionCount: 1, actualStart: start, actualEnd: end)
        )))
        #expect(request.taskStatus == "failed")
        #expect(request.outcomeStatus == .partial)
        #expect(request.completionRatio == 0.4)
        #expect(request.stoppedEarly == true)
        #expect(request.failureReason == .underestimatedTime)
    }

    @Test func abandonedHasZeroRatioAndStopsEarly() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .abandoned, failureReason: .lowReadiness, actualStart: start, actualEnd: end)
        )))
        #expect(request.taskStatus == "failed")
        #expect(request.outcomeStatus == .abandoned)
        #expect(request.completionRatio == 0)
        #expect(request.stoppedEarly == true)
        #expect(request.failureReason == .lowReadiness)
    }

    @Test func notStartedSendsNoTimesOrActivity() throws {
        let request = try #require(request(from: build(OutcomeInput(result: .notStarted))))
        #expect(request.taskStatus == "failed")
        #expect(request.outcomeStatus == .notStarted)
        #expect(request.completionRatio == 0)
        #expect(request.stoppedEarly == false)
        #expect(request.interruptionCount == 0)
        #expect(request.failureReason == nil)
        #expect(request.actualStartTime == nil)
        #expect(request.actualEndTime == nil)
        #expect(request.activeMinutes == nil)
    }

    @Test func notStartedKeepsOptionalReason() throws {
        let request = try #require(request(from: build(OutcomeInput(result: .notStarted, failureReason: .other))))
        #expect(request.failureReason == .other)
    }

    @Test func stillWorkingNeverValidates() throws {
        let submission = try build(OutcomeInput(result: .stillWorking, interruptionCount: -5))
        #expect(submission == .keepActive)
    }

    // MARK: - Active versus unstarted

    @Test func activeExecutionCompletesWithoutTimes() throws {
        let submission = try build(OutcomeInput(result: .completed), active: active)
        guard case .completeActive(let executionID, let request) = submission else {
            Issue.record("expected completeActive"); return
        }
        #expect(executionID == "exec-1")
        #expect(request.actualStartTime == nil)
        #expect(request.actualEndTime == nil)
    }

    @Test func activeExecutionAcceptsManualTimes() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .abandoned, failureReason: .other, actualStart: start, actualEnd: end), active: active
        )))
        #expect(request.actualStartTime == start)
    }

    @Test func notStartedWhileActiveIsRejected() {
        #expect(throws: OutcomeValidationError.notStartedWhileActive) {
            try build(OutcomeInput(result: .notStarted), active: active)
        }
    }

    @Test func unstartedOutcomeRequiresTimes() {
        #expect(throws: OutcomeValidationError.missingActualTimes) {
            try build(OutcomeInput(result: .completed))
        }
    }

    // MARK: - Failure reason

    @Test func partialRequiresReason() {
        #expect(throws: OutcomeValidationError.missingFailureReason) {
            try build(OutcomeInput(result: .partial(percent: 50), actualStart: start, actualEnd: end))
        }
    }

    @Test func abandonedRequiresReason() {
        #expect(throws: OutcomeValidationError.missingFailureReason) {
            try build(OutcomeInput(result: .abandoned, actualStart: start, actualEnd: end))
        }
    }

    // MARK: - Ratios and counts

    @Test(arguments: [0, 100, -1, 150])
    func partialPercentOutsideOneToNinetyNineIsRejected(percent: Int) {
        #expect(throws: OutcomeValidationError.invalidCompletionPercent) {
            try build(OutcomeInput(result: .partial(percent: percent), failureReason: .other, actualStart: start, actualEnd: end))
        }
    }

    @Test(arguments: [1, 99])
    func partialPercentBoundariesAreAccepted(percent: Int) throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .partial(percent: percent), failureReason: .other, actualStart: start, actualEnd: end)
        )))
        #expect(request.completionRatio == Double(percent) / 100)
    }

    @Test(arguments: [-1, 10_001])
    func interruptionCountOutsideRangeIsRejected(count: Int) {
        #expect(throws: OutcomeValidationError.invalidInterruptionCount) {
            try build(OutcomeInput(result: .completed, interruptionCount: count, actualStart: start, actualEnd: end))
        }
    }

    @Test(arguments: [0, 10_000])
    func interruptionCountBoundariesAreAccepted(count: Int) throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .completed, interruptionCount: count, actualStart: start, actualEnd: end)
        )))
        #expect(request.interruptionCount == count)
    }

    @Test func notStartedRejectsInterruptions() {
        #expect(throws: OutcomeValidationError.activityNotAllowedForNotStarted) {
            try build(OutcomeInput(result: .notStarted, interruptionCount: 1))
        }
    }

    @Test func notStartedRejectsTimes() {
        #expect(throws: OutcomeValidationError.timesNotAllowedForNotStarted) {
            try build(OutcomeInput(result: .notStarted, actualStart: start, actualEnd: end))
        }
    }

    // MARK: - Timestamps

    @Test func endBeforeStartIsRejected() {
        #expect(throws: OutcomeValidationError.endBeforeStart) {
            try build(OutcomeInput(result: .completed, actualStart: end, actualEnd: start))
        }
    }

    @Test func endEqualToStartIsAccepted() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .completed, actualStart: start, actualEnd: start)
        )))
        #expect(request.actualEndTime == start)
    }

    @Test func endWithinFiveMinutesOfNowIsAccepted() throws {
        let soon = now.addingTimeInterval(299)
        let request = try #require(request(from: build(
            OutcomeInput(result: .completed, actualStart: start, actualEnd: soon)
        )))
        #expect(request.actualEndTime == soon)
    }

    @Test func endMoreThanFiveMinutesAheadIsRejected() {
        #expect(throws: OutcomeValidationError.endInFuture) {
            try build(OutcomeInput(result: .completed, actualStart: start, actualEnd: now.addingTimeInterval(301)))
        }
    }

    @Test func onlyOneTimeIsRejected() {
        #expect(throws: OutcomeValidationError.incompleteActualTimes) {
            try build(OutcomeInput(result: .completed, actualStart: start))
        }
        #expect(throws: OutcomeValidationError.incompleteActualTimes) {
            try build(OutcomeInput(result: .completed, actualEnd: end))
        }
    }

    // MARK: - Active minutes

    @Test func activeMinutesWithinElapsedIsAccepted() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .completed, actualStart: start, actualEnd: end, activeMinutes: 50)
        )))
        #expect(request.activeMinutes == 50)
    }

    @Test func activeMinutesBeyondElapsedIsRejected() {
        #expect(throws: OutcomeValidationError.activeMinutesExceedElapsed) {
            try build(OutcomeInput(result: .completed, actualStart: start, actualEnd: end, activeMinutes: 51))
        }
    }

    @Test func negativeActiveMinutesIsRejected() {
        #expect(throws: OutcomeValidationError.invalidActiveMinutes) {
            try build(OutcomeInput(result: .completed, actualStart: start, actualEnd: end, activeMinutes: -1))
        }
    }

    // MARK: - Idempotency key

    @Test func idempotencyKeyIsTaskIDOnlyWhenUUID() {
        #expect(OutcomeRequestBuilder.idempotencyKey(for: taskID) == taskID)
        #expect(OutcomeRequestBuilder.idempotencyKey(for: "preview-1") == nil)
    }

    // MARK: - Wire format

    @Test func encodedBodyMatchesBackendContract() throws {
        let request = try #require(request(from: build(
            OutcomeInput(result: .partial(percent: 25), failureReason: .interruption, interruptionCount: 3, actualStart: start, actualEnd: end)
        )))

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])

        #expect(object["task_status"] as? String == "failed")
        #expect(object["outcome_status"] as? String == "partial")
        #expect(object["completion_ratio"] as? Double == 0.25)
        #expect(object["stopped_early"] as? Bool == true)
        #expect(object["failure_reason"] as? String == "interruption")
        #expect(object["interruption_count"] as? Int == 3)
        #expect((object["actual_start_time"] as? String)?.hasSuffix("Z") == true)
        #expect(object["active_minutes"] == nil)
    }

    @Test func notStartedBodyOmitsTimes() throws {
        let request = try #require(request(from: build(OutcomeInput(result: .notStarted))))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])

        #expect(object["actual_start_time"] == nil)
        #expect(object["actual_end_time"] == nil)
        #expect(object["failure_reason"] == nil)
        #expect(object["outcome_status"] as? String == "not_started")
    }
}
