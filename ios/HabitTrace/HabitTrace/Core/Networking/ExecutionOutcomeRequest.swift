import Foundation

/// Body for `POST /executions`, `PATCH /executions/{id}/complete`, and
/// `PATCH /executions/{id}` (revise). Mirrors the backend's `ExecutionTimes`.
///
/// `nil` fields are omitted from the JSON so the server applies its own
/// defaults. Dates are encoded as ISO 8601 with a UTC offset, which the
/// server requires. See `OutcomeStatus` for the validation rules the
/// server enforces on these combinations.
struct ExecutionOutcomeRequest: Encodable, Equatable {
    /// "success" or "failed". Use `OutcomeStatus.taskStatus`.
    var taskStatus: String
    var outcomeStatus: OutcomeStatus?
    /// 0...1. Required strictly between 0 and 1 for `partial`.
    var completionRatio: Double?
    var interruptionCount: Int = 0
    var stoppedEarly: Bool = false
    /// Required for failed outcomes other than `notStarted`.
    var failureReason: FailureReason?
    var activeMinutes: Int?
    /// Both times or neither. Omit when completing an active execution so
    /// the server uses its recorded start and the current time.
    var actualStartTime: Date?
    var actualEndTime: Date?
}

/// Body for `POST /executions`: an outcome plus the task it belongs to.
struct ExecutionLogRequest: Encodable {
    let taskId: String
    /// A UUID string. The PWA uses the task id so a plan is logged once.
    let idempotencyKey: String?
    let taskStatus: String
    let outcomeStatus: OutcomeStatus?
    let completionRatio: Double?
    let interruptionCount: Int
    let stoppedEarly: Bool
    let failureReason: FailureReason?
    let activeMinutes: Int?
    let actualStartTime: Date?
    let actualEndTime: Date?

    init(taskId: String, idempotencyKey: String?, outcome: ExecutionOutcomeRequest) {
        self.taskId = taskId
        self.idempotencyKey = idempotencyKey
        taskStatus = outcome.taskStatus
        outcomeStatus = outcome.outcomeStatus
        completionRatio = outcome.completionRatio
        interruptionCount = outcome.interruptionCount
        stoppedEarly = outcome.stoppedEarly
        failureReason = outcome.failureReason
        activeMinutes = outcome.activeMinutes
        actualStartTime = outcome.actualStartTime
        actualEndTime = outcome.actualEndTime
    }
}
