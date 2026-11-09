import Foundation
import Testing
@testable import HabitTrace

/// Pure validation and request construction against the main (ae6521c)
/// contract: optional times, optional reasons, nullable interruptions.
struct OutcomeRequestBuilderTests {
    private let taskID = "6D2C0F0E-1F6B-4C7D-9A3E-2B1C4D5E6F70"
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private var active: HabitTraceExecution {
        HabitTraceExecution(
            id: "exec-1", taskId: taskID, userId: "user",
            actualStartTime: ISO8601DateFormatter().string(from: now.addingTimeInterval(-1800)),
            actualEndTime: nil, interruptionCount: nil, stoppedEarly: false,
            taskStatus: nil, failureReason: nil, createdAt: "c"
        )
    }

    private func finished(outcome: OutcomeStatus, start: Date?, end: Date?, minutes: Int? = nil, stoppedEarly: Bool = false) -> HabitTraceExecution {
        let formatter = ISO8601DateFormatter()
        return HabitTraceExecution(
            id: "exec-f", taskId: taskID, userId: "user",
            actualStartTime: start.map(formatter.string),
            actualEndTime: end.map(formatter.string),
            interruptionCount: nil, stoppedEarly: stoppedEarly,
            taskStatus: outcome.taskStatus, failureReason: nil,
            outcomeStatus: outcome, completionRatio: outcome == .completed ? 1 : 0,
            activeMinutes: minutes, createdAt: "c"
        )
    }

    private func build(_ input: OutcomeInput, active: HabitTraceExecution? = nil) throws -> OutcomeSubmission {
        try OutcomeRequestBuilder.build(input, taskID: taskID, activeExecution: active, now: now)
    }

    private func encoded(_ request: ExecutionOutcomeRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
    }

    // MARK: - Completed

    @Test func completedWithoutTimeSendsUnknownEnd() throws {
        let request = try build(OutcomeInput(choice: .completed)).request
        #expect(request.taskStatus == "success")
        #expect(request.outcomeStatus == .completed)
        #expect(request.completionRatio == 1)
        #expect(request.interruptionCount == nil)
        #expect(request.stoppedEarly == false)
        #expect(request.actualEndUnknown == true)
        #expect(request.actualEndTime == nil)
        #expect(request.actualStartTime == nil)
    }

    @Test func completedWithTimeSendsEndOnly() throws {
        let finishedAt = now.addingTimeInterval(-600)
        let request = try build(OutcomeInput(choice: .completed, finishedAt: finishedAt)).request
        #expect(request.actualEndTime == finishedAt)
        #expect(request.actualStartTime == nil)
        #expect(request.actualEndUnknown == false)
    }

    @Test func completedRejectsFutureFinish() {
        #expect(throws: OutcomeValidationError.finishInFuture) {
            try build(OutcomeInput(choice: .completed, finishedAt: now.addingTimeInterval(301)))
        }
    }

    @Test func completedAcceptsFinishWithinTolerance() throws {
        let request = try build(OutcomeInput(choice: .completed, finishedAt: now.addingTimeInterval(299))).request
        #expect(request.actualEndTime != nil)
    }

    @Test func completedRejectsFinishBeforeRecordedStart() {
        #expect(throws: OutcomeValidationError.finishBeforeStart) {
            try build(OutcomeInput(choice: .completed, finishedAt: now.addingTimeInterval(-3600)), active: active)
        }
    }

    // MARK: - Not completed

    @Test func didNotStartSendsNotStartedWithoutTimes() throws {
        let request = try build(OutcomeInput(choice: .notCompleted, didNotStart: true, reason: .other)).request
        #expect(request.taskStatus == "failed")
        #expect(request.outcomeStatus == .notStarted)
        #expect(request.completionRatio == 0)
        #expect(request.interruptionCount == 0)
        #expect(request.stoppedEarly == false)
        #expect(request.failureReason == .other)
        #expect(request.actualEndUnknown == false)
        #expect(request.activeMinutes == nil)
    }

    @Test func didNotStartIsRejectedWhileActive() {
        #expect(throws: OutcomeValidationError.notStartedWhileActive) {
            try build(OutcomeInput(choice: .notCompleted, didNotStart: true), active: active)
        }
    }

    @Test func abandonedBlankLeavesEverythingUnknown() throws {
        let request = try build(OutcomeInput(choice: .notCompleted)).request
        #expect(request.outcomeStatus == .abandoned)
        #expect(request.completionRatio == 0)
        #expect(request.interruptionCount == nil)
        #expect(request.stoppedEarly == false)
        #expect(request.activeMinutes == nil)
        #expect(request.failureReason == nil)
        #expect(request.actualEndUnknown == true)
    }

    @Test func abandonedWithMinutesStopsEarly() throws {
        let request = try build(OutcomeInput(choice: .notCompleted, minutesSpent: 20, reason: .interruption)).request
        #expect(request.activeMinutes == 20)
        #expect(request.stoppedEarly == true)
        #expect(request.failureReason == .interruption)
    }

    @Test func abandonedWithZeroMinutesDoesNotStopEarly() throws {
        let request = try build(OutcomeInput(choice: .notCompleted, minutesSpent: 0)).request
        #expect(request.activeMinutes == 0)
        #expect(request.stoppedEarly == false)
    }

    @Test(arguments: [1441, 5000])
    func minutesSpentOutsideRangeIsRejected(minutes: Int) {
        #expect(throws: OutcomeValidationError.invalidMinutesSpent) {
            try build(OutcomeInput(choice: .notCompleted, minutesSpent: minutes))
        }
    }

    @Test func noChoiceIsRejected() {
        #expect(throws: OutcomeValidationError.noChoice) {
            try build(OutcomeInput())
        }
    }

    // MARK: - Routing

    @Test func activeExecutionRoutesToComplete() throws {
        guard case .completeActive(let executionID, _) = try build(OutcomeInput(choice: .completed), active: active) else {
            Issue.record("expected completeActive"); return
        }
        #expect(executionID == "exec-1")
    }

    @Test func unstartedRoutesToLogWithIdempotencyKey() throws {
        guard case .log(let id, let key, _) = try build(OutcomeInput(choice: .completed)) else {
            Issue.record("expected log"); return
        }
        #expect(id == taskID)
        #expect(key == taskID)
        #expect(OutcomeRequestBuilder.idempotencyKey(for: "preview-1") == nil)
    }

    // MARK: - Wire format

    @Test func interruptionsAreEncodedAsExplicitNull() throws {
        let object = try encoded(try build(OutcomeInput(choice: .completed)).request)
        #expect(object.keys.contains("interruption_count"))
        #expect(object["interruption_count"] is NSNull)
        #expect(object["actual_end_unknown"] as? Bool == true)
        #expect(object["failure_reason"] == nil)
        #expect(object["actual_end_time"] == nil)
    }

    @Test func abandonedWireFormatMatchesPWA() throws {
        let object = try encoded(try build(OutcomeInput(choice: .notCompleted, minutesSpent: 20, reason: .interruption)).request)
        #expect(object["task_status"] as? String == "failed")
        #expect(object["outcome_status"] as? String == "abandoned")
        #expect(object["completion_ratio"] as? Double == 0)
        #expect(object["interruption_count"] is NSNull)
        #expect(object["stopped_early"] as? Bool == true)
        #expect(object["active_minutes"] as? Int == 20)
        #expect(object["failure_reason"] as? String == "interruption")
        #expect(object["actual_end_unknown"] as? Bool == true)
    }

    @Test func logRequestAddsTaskAndKey() throws {
        let log = ExecutionLogRequest(taskId: taskID, idempotencyKey: taskID, outcome: try build(OutcomeInput(choice: .completed)).request)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(log)) as? [String: Any])
        #expect(object["task_id"] as? String == taskID)
        #expect(object["idempotency_key"] as? String == taskID)
        #expect(object["task_status"] as? String == "success")
    }

    // MARK: - Revision

    @Test func revisionNotStartedSkipsValidation() throws {
        let existing = finished(outcome: .abandoned, start: nil, end: nil)
        let request = try OutcomeRequestBuilder.buildRevision(
            RevisionInput(result: .notStarted, interruptions: 99_999, reason: .other),
            existing: existing, now: now
        )
        #expect(request.outcomeStatus == .notStarted)
        #expect(request.interruptionCount == 0)
        #expect(request.failureReason == .other)
        #expect(request.actualStartTime == nil)
    }

    @Test func revisionPartialRequiresPercent() {
        let existing = finished(outcome: .abandoned, start: nil, end: nil)
        #expect(throws: OutcomeValidationError.invalidProgress) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .partial), existing: existing, now: now)
        }
        #expect(throws: OutcomeValidationError.invalidProgress) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .partial, progressPercent: 100), existing: existing, now: now)
        }
    }

    @Test func revisionPartialMapsRatioAndStopsEarly() throws {
        let existing = finished(outcome: .abandoned, start: nil, end: nil)
        let request = try OutcomeRequestBuilder.buildRevision(
            RevisionInput(result: .partial, interruptions: 2, progressPercent: 40),
            existing: existing, now: now
        )
        #expect(request.completionRatio == 0.4)
        #expect(request.interruptionCount == 2)
        #expect(request.stoppedEarly == true)
    }

    @Test func revisionKeepsStoppedEarlyWhenResultUnchanged() throws {
        let existing = finished(outcome: .abandoned, start: nil, end: nil, stoppedEarly: true)
        let request = try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .abandoned), existing: existing, now: now)
        #expect(request.stoppedEarly == true)
    }

    @Test func revisionInterruptionsOutsideRangeIsRejected() {
        let existing = finished(outcome: .abandoned, start: nil, end: nil)
        #expect(throws: OutcomeValidationError.invalidInterruptions) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .abandoned, interruptions: 10_001), existing: existing, now: now)
        }
    }

    @Test func revisionRejectsFutureAndReversedTimes() {
        let existing = finished(outcome: .abandoned, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-600))
        #expect(throws: OutcomeValidationError.timeInFuture("finish")) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .abandoned, actualEnd: now.addingTimeInterval(600)), existing: existing, now: now)
        }
        #expect(throws: OutcomeValidationError.endBeforeStart) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .abandoned, actualStart: now.addingTimeInterval(-300)), existing: existing, now: now)
        }
    }

    @Test func revisionRejectsMinutesBeyondElapsed() {
        let existing = finished(outcome: .abandoned, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-600))
        #expect(throws: OutcomeValidationError.minutesExceedElapsed) {
            try OutcomeRequestBuilder.buildRevision(RevisionInput(result: .abandoned, minutesSpent: 51), existing: existing, now: now)
        }
    }

    @Test func revisionCompletedKeepsExistingMinutesAndClearsReason() throws {
        let existing = finished(outcome: .abandoned, start: nil, end: nil, minutes: 25)
        let request = try OutcomeRequestBuilder.buildRevision(
            RevisionInput(result: .completed, minutesSpent: 10, reason: .other),
            existing: existing, now: now
        )
        #expect(request.taskStatus == "success")
        #expect(request.completionRatio == 1)
        #expect(request.activeMinutes == 25)
        #expect(request.failureReason == nil)
    }

    // MARK: - Confirmation text

    @Test func confirmationTextMatchesPWA() {
        let completedNoEnd = finished(outcome: .completed, start: nil, end: nil)
        #expect(OutcomeRequestBuilder.confirmation(for: completedNoEnd, scheduledEnd: "8:00 PM") == "Marked completed · scheduled end 8:00 PM.")
        #expect(OutcomeRequestBuilder.confirmation(for: completedNoEnd, scheduledEnd: nil) == "Marked completed.")

        let notStarted = finished(outcome: .notStarted, start: nil, end: nil)
        #expect(OutcomeRequestBuilder.confirmation(for: notStarted, scheduledEnd: nil) == "Marked not completed · not started.")

        let abandonedMinutes = finished(outcome: .abandoned, start: nil, end: nil, minutes: 15)
        #expect(OutcomeRequestBuilder.confirmation(for: abandonedMinutes, scheduledEnd: nil) == "Marked not completed · 15 min recorded.")

        let abandoned = finished(outcome: .abandoned, start: nil, end: nil)
        #expect(OutcomeRequestBuilder.confirmation(for: abandoned, scheduledEnd: nil) == "Marked not completed.")
    }
}
