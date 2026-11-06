import Foundation

/// What the user chose when logging an outcome. Mirrors the PWA's
/// `MobileResult`: four recorded statuses plus "Still working", which
/// only makes sure the plan is started.
nonisolated enum OutcomeResult: Equatable, Sendable {
    case completed
    /// Percent complete, 1 through 99.
    case partial(percent: Int)
    case abandoned
    case notStarted
    case stillWorking

    /// The server status this result records, or nil for `stillWorking`.
    var status: OutcomeStatus? {
        switch self {
        case .completed: .completed
        case .partial: .partial
        case .abandoned: .abandoned
        case .notStarted: .notStarted
        case .stillWorking: nil
        }
    }
}

/// Everything the outcome sheet collects. Validation happens in
/// `OutcomeRequestBuilder`, not here.
nonisolated struct OutcomeInput: Equatable, Sendable {
    var result: OutcomeResult
    var failureReason: FailureReason?
    var interruptionCount = 0
    /// Both or neither. Required when logging a plan that was never started.
    var actualStart: Date?
    var actualEnd: Date?
    /// Minutes actively worked. Never sent by the PWA; optional here.
    var activeMinutes: Int?

    init(
        result: OutcomeResult,
        failureReason: FailureReason? = nil,
        interruptionCount: Int = 0,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        activeMinutes: Int? = nil
    ) {
        self.result = result
        self.failureReason = failureReason
        self.interruptionCount = interruptionCount
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.activeMinutes = activeMinutes
    }
}

/// Reasons an outcome cannot be sent. Messages reuse the PWA's wording
/// where it has one.
nonisolated enum OutcomeValidationError: Error, Equatable, LocalizedError {
    case missingFailureReason
    case invalidCompletionPercent
    case invalidInterruptionCount
    case missingActualTimes
    case incompleteActualTimes
    case endBeforeStart
    case endInFuture
    case timesNotAllowedForNotStarted
    case activityNotAllowedForNotStarted
    case notStartedWhileActive
    case invalidActiveMinutes
    case activeMinutesExceedElapsed

    var errorDescription: String? {
        switch self {
        case .missingFailureReason:
            "Choose what got in the way."
        case .invalidCompletionPercent, .invalidInterruptionCount:
            "Enter an interruption count and, for partial progress, a completion percentage from 1 to 99."
        case .missingActualTimes, .incompleteActualTimes, .endBeforeStart, .endInFuture:
            "Enter when you actually started and finished. The end must follow the start and cannot be in the future."
        case .timesNotAllowedForNotStarted, .activityNotAllowedForNotStarted:
            "A plan you didn't start can't have times or interruptions."
        case .notStartedWhileActive:
            "This plan has a recorded start. Record its actual outcome instead."
        case .invalidActiveMinutes, .activeMinutesExceedElapsed:
            "Active minutes can't exceed the time between start and finish."
        }
    }
}

/// The network operation an outcome resolves to.
nonisolated enum OutcomeSubmission: Equatable, Sendable {
    /// "Still working": ensure the plan is started. No outcome is written.
    case keepActive
    /// `PATCH /executions/{id}/complete` on the task's active execution.
    case completeActive(executionID: String, request: ExecutionOutcomeRequest)
    /// `POST /executions` for a task with no active execution. The
    /// idempotency key is the task id when it is a UUID, so a retry
    /// returns the same record instead of creating another.
    case log(taskID: String, idempotencyKey: String?, request: ExecutionOutcomeRequest)
}

/// Turns an `OutcomeInput` into a request that the backend will accept,
/// applying the rules from `ExecutionFacts`, `ExecutionTimes`, and
/// `ExecutionCreate` so invalid outcomes never reach the network.
enum OutcomeRequestBuilder {
    static let interruptionRange = 0...10_000
    static let partialPercentRange = 1...99
    /// The server rejects an end more than five minutes in the future.
    static let futureTolerance: TimeInterval = 300

    static func build(
        _ input: OutcomeInput,
        taskID: String,
        activeExecution: HabitTraceExecution?,
        now: Date = .now
    ) throws -> OutcomeSubmission {
        guard let status = input.result.status else {
            return .keepActive
        }

        if activeExecution != nil, status == .notStarted {
            throw OutcomeValidationError.notStartedWhileActive
        }

        // Completion ratio.
        let completionRatio: Double
        switch input.result {
        case .completed:
            completionRatio = 1
        case .partial(let percent):
            guard partialPercentRange.contains(percent) else {
                throw OutcomeValidationError.invalidCompletionPercent
            }
            completionRatio = Double(percent) / 100
        case .abandoned, .notStarted:
            completionRatio = 0
        case .stillWorking:
            return .keepActive
        }

        // Interruptions and activity.
        if status == .notStarted {
            if input.interruptionCount != 0 || (input.activeMinutes ?? 0) != 0 {
                throw OutcomeValidationError.activityNotAllowedForNotStarted
            }
        } else {
            guard interruptionRange.contains(input.interruptionCount) else {
                throw OutcomeValidationError.invalidInterruptionCount
            }
            if let minutes = input.activeMinutes, minutes < 0 {
                throw OutcomeValidationError.invalidActiveMinutes
            }
        }

        // Failure reason: required for failed outcomes other than not started.
        let failureReason: FailureReason?
        switch status {
        case .completed:
            failureReason = nil
        case .partial, .abandoned:
            guard let reason = input.failureReason else {
                throw OutcomeValidationError.missingFailureReason
            }
            failureReason = reason
        case .notStarted:
            failureReason = input.failureReason
        }

        // Actual times.
        var actualStart: Date?
        var actualEnd: Date?

        switch (input.actualStart, input.actualEnd) {
        case (nil, nil):
            if status != .notStarted, activeExecution == nil {
                // Logging a never-started plan: the server requires both times.
                throw OutcomeValidationError.missingActualTimes
            }
        case (let start?, let end?):
            if status == .notStarted {
                throw OutcomeValidationError.timesNotAllowedForNotStarted
            }
            if end < start {
                throw OutcomeValidationError.endBeforeStart
            }
            if end.timeIntervalSince(now) > futureTolerance {
                throw OutcomeValidationError.endInFuture
            }
            if let minutes = input.activeMinutes {
                let elapsedMinutes = Int(end.timeIntervalSince(start) / 60)
                if minutes > elapsedMinutes {
                    throw OutcomeValidationError.activeMinutesExceedElapsed
                }
            }
            actualStart = start
            actualEnd = end
        default:
            if status == .notStarted {
                throw OutcomeValidationError.timesNotAllowedForNotStarted
            }
            throw OutcomeValidationError.incompleteActualTimes
        }

        let request = ExecutionOutcomeRequest(
            taskStatus: status.taskStatus,
            outcomeStatus: status,
            completionRatio: completionRatio,
            interruptionCount: status == .notStarted ? 0 : input.interruptionCount,
            stoppedEarly: status.stoppedEarly,
            failureReason: failureReason,
            activeMinutes: status == .notStarted ? nil : input.activeMinutes,
            actualStartTime: actualStart,
            actualEndTime: actualEnd
        )

        if let activeExecution {
            return .completeActive(executionID: activeExecution.id, request: request)
        }

        return .log(taskID: taskID, idempotencyKey: idempotencyKey(for: taskID), request: request)
    }

    /// The server types `idempotency_key` as a UUID. Task ids are UUIDs in
    /// production; anything else is sent without a key rather than rejected.
    static func idempotencyKey(for taskID: String) -> String? {
        UUID(uuidString: taskID) == nil ? nil : taskID
    }
}
