import Foundation

/// Body for `POST /executions`, `PATCH /executions/{id}/complete`, and
/// `PATCH /executions/{id}` (revise). Mirrors the backend's `ExecutionTimes`
/// at main (ae6521c), where every fact may be unknown.
///
/// Encoding rules follow the PWA exactly:
/// - `interruption_count` is always present; nil is sent as JSON null,
///   which the server stores as "not reported" (an omitted key would be
///   read as 0).
/// - `failure_reason`, `active_minutes`, and both times are omitted when nil.
/// - `actual_end_unknown` is sent only when true, telling the server not to
///   stamp the request time as the finish of a running timer.
nonisolated struct ExecutionOutcomeRequest: Encodable, Equatable, Sendable {
    /// "success" or "failed". Use `OutcomeStatus.taskStatus`.
    var taskStatus: String
    var outcomeStatus: OutcomeStatus?
    /// 0...1. Strictly between 0 and 1 for `partial`.
    var completionRatio: Double?
    /// nil means not reported.
    var interruptionCount: Int?
    var stoppedEarly = false
    var failureReason: FailureReason?
    /// Minutes actually spent; nil means unknown.
    var activeMinutes: Int?
    var actualStartTime: Date?
    var actualEndTime: Date?
    var actualEndUnknown = false

    init(
        taskStatus: String,
        outcomeStatus: OutcomeStatus? = nil,
        completionRatio: Double? = nil,
        interruptionCount: Int? = nil,
        stoppedEarly: Bool = false,
        failureReason: FailureReason? = nil,
        activeMinutes: Int? = nil,
        actualStartTime: Date? = nil,
        actualEndTime: Date? = nil,
        actualEndUnknown: Bool = false
    ) {
        self.taskStatus = taskStatus
        self.outcomeStatus = outcomeStatus
        self.completionRatio = completionRatio
        self.interruptionCount = interruptionCount
        self.stoppedEarly = stoppedEarly
        self.failureReason = failureReason
        self.activeMinutes = activeMinutes
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.actualEndUnknown = actualEndUnknown
    }

    enum CodingKeys: String, CodingKey {
        case taskStatus
        case outcomeStatus
        case completionRatio
        case interruptionCount
        case stoppedEarly
        case failureReason
        case activeMinutes
        case actualStartTime
        case actualEndTime
        case actualEndUnknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskStatus, forKey: .taskStatus)
        try container.encodeIfPresent(outcomeStatus, forKey: .outcomeStatus)
        try container.encodeIfPresent(completionRatio, forKey: .completionRatio)
        try container.encode(interruptionCount, forKey: .interruptionCount)
        try container.encode(stoppedEarly, forKey: .stoppedEarly)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
        try container.encodeIfPresent(activeMinutes, forKey: .activeMinutes)
        try container.encodeIfPresent(actualStartTime, forKey: .actualStartTime)
        try container.encodeIfPresent(actualEndTime, forKey: .actualEndTime)
        if actualEndUnknown {
            try container.encode(true, forKey: .actualEndUnknown)
        }
    }
}

/// Body for `POST /executions`: an outcome plus the task it belongs to.
nonisolated struct ExecutionLogRequest: Encodable, Sendable {
    let taskId: String
    /// A UUID string. The PWA uses the task id so a plan is logged once.
    let idempotencyKey: String?
    let outcome: ExecutionOutcomeRequest

    private enum ExtraKeys: String, CodingKey {
        case taskId
        case idempotencyKey
    }

    func encode(to encoder: Encoder) throws {
        try outcome.encode(to: encoder)
        var container = encoder.container(keyedBy: ExtraKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
    }
}
