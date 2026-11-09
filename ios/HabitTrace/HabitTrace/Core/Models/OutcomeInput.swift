import Foundation

/// What the user picked in the outcome sheet. Mirrors `lib/outcome.ts`
/// at main: Completed or Not completed, each with optional details.
nonisolated enum OutcomeChoice: Equatable, Sendable {
    case completed
    case notCompleted
}

/// Everything the outcome sheet collects. Validation lives in
/// `OutcomeRequestBuilder`.
nonisolated struct OutcomeInput: Equatable, Sendable {
    var choice: OutcomeChoice?
    /// Completed only. nil means "leave blank", which sends `actual_end_unknown`.
    var finishedAt: Date?
    /// Not completed only. Hidden when the plan has a recorded start.
    var didNotStart = false
    /// Not completed only. nil stays unrecorded. 0...1440.
    var minutesSpent: Int?
    /// Not completed only. nil means "Prefer not to say".
    var reason: FailureReason?

    init(
        choice: OutcomeChoice? = nil,
        finishedAt: Date? = nil,
        didNotStart: Bool = false,
        minutesSpent: Int? = nil,
        reason: FailureReason? = nil
    ) {
        self.choice = choice
        self.finishedAt = finishedAt
        self.didNotStart = didNotStart
        self.minutesSpent = minutesSpent
        self.reason = reason
    }
}

/// Fields of the "Edit logged plan" form that change the execution.
/// Mirrors `RevisionDraft` in `lib/outcome.ts`.
nonisolated struct RevisionInput: Equatable, Sendable {
    var result: OutcomeStatus
    /// nil keeps the stored value; the UI never clears a stored time.
    var actualStart: Date?
    var actualEnd: Date?
    /// nil means not reported.
    var interruptions: Int?
    /// 1...99, required for partial.
    var progressPercent: Int?
    var minutesSpent: Int?
    var reason: FailureReason?

    init(
        result: OutcomeStatus,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        interruptions: Int? = nil,
        progressPercent: Int? = nil,
        minutesSpent: Int? = nil,
        reason: FailureReason? = nil
    ) {
        self.result = result
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.interruptions = interruptions
        self.progressPercent = progressPercent
        self.minutesSpent = minutesSpent
        self.reason = reason
    }
}

/// Reasons an outcome cannot be sent, with the PWA's wording.
nonisolated enum OutcomeValidationError: Error, Equatable, LocalizedError {
    case noChoice
    case invalidFinishTime
    case finishInFuture
    case finishBeforeStart
    case notStartedWhileActive
    case invalidMinutesSpent
    case invalidInterruptions
    case invalidProgress
    case savedTimeRemoved(String)
    case invalidTime(String)
    case timeInFuture(String)
    case endBeforeStart
    case minutesExceedElapsed

    var errorDescription: String? {
        switch self {
        case .noChoice:
            "Choose Completed or Not completed."
        case .invalidFinishTime:
            "Enter a valid finish time."
        case .finishInFuture:
            "The finish time can’t be in the future."
        case .finishBeforeStart:
            "The finish time can’t be before you started."
        case .notStartedWhileActive:
            "This plan has a recorded start, so it can’t be marked as not started."
        case .invalidMinutesSpent:
            "Minutes spent must be a whole number from 0 to 1440."
        case .invalidInterruptions:
            "Interruptions must be a whole number from 0 to 10000."
        case .invalidProgress:
            "Enter a completion percentage from 1 to 99."
        case .savedTimeRemoved(let label):
            "The saved \(label) time can be corrected but not removed."
        case .invalidTime(let label):
            "Enter a valid \(label) time."
        case .timeInFuture(let label):
            "The \(label) time can’t be in the future."
        case .endBeforeStart:
            "The finish time must follow the start time."
        case .minutesExceedElapsed:
            "Minutes spent can’t exceed the time between start and finish."
        }
    }
}

/// The network operation an outcome resolves to.
nonisolated enum OutcomeSubmission: Equatable, Sendable {
    /// `PATCH /executions/{id}/complete` on the task's active execution.
    case completeActive(executionID: String, request: ExecutionOutcomeRequest)
    /// `POST /executions` for a task with no active execution. The
    /// idempotency key is the task id when it is a UUID, so a retry
    /// returns the same record instead of creating another.
    case log(taskID: String, idempotencyKey: String?, request: ExecutionOutcomeRequest)

    var request: ExecutionOutcomeRequest {
        switch self {
        case .completeActive(_, let request), .log(_, _, let request): request
        }
    }
}

/// Builds backend requests from sheet input, applying `lib/outcome.ts`
/// rules so invalid outcomes never reach the network.
enum OutcomeRequestBuilder {
    static let minutesSpentRange = 0...1440
    static let interruptionRange = 0...10_000
    static let progressRange = 1...99
    /// The server rejects times more than five minutes in the future.
    static let futureTolerance: TimeInterval = 300

    // MARK: - Outcome sheet

    static func build(
        _ input: OutcomeInput,
        taskID: String,
        activeExecution: HabitTraceExecution?,
        now: Date = .now
    ) throws -> OutcomeSubmission {
        let request = try buildRequest(input, activeStart: activeExecution?.actualStartDate, now: now)

        if let activeExecution {
            return .completeActive(executionID: activeExecution.id, request: request)
        }
        return .log(taskID: taskID, idempotencyKey: idempotencyKey(for: taskID), request: request)
    }

    /// `buildOutcomeInput` from the PWA.
    static func buildRequest(
        _ input: OutcomeInput,
        activeStart: Date?,
        now: Date = .now
    ) throws -> ExecutionOutcomeRequest {
        guard let choice = input.choice else {
            throw OutcomeValidationError.noChoice
        }

        switch choice {
        case .completed:
            var request = ExecutionOutcomeRequest(
                taskStatus: OutcomeStatus.completed.taskStatus,
                outcomeStatus: .completed,
                completionRatio: 1,
                interruptionCount: nil,
                stoppedEarly: false
            )

            guard let finished = input.finishedAt else {
                request.actualEndUnknown = true
                return request
            }
            if finished.timeIntervalSince(now) > futureTolerance {
                throw OutcomeValidationError.finishInFuture
            }
            if let activeStart, finished < activeStart {
                throw OutcomeValidationError.finishBeforeStart
            }
            request.actualEndTime = finished
            return request

        case .notCompleted:
            if input.didNotStart {
                if activeStart != nil {
                    throw OutcomeValidationError.notStartedWhileActive
                }
                return ExecutionOutcomeRequest(
                    taskStatus: OutcomeStatus.notStarted.taskStatus,
                    outcomeStatus: .notStarted,
                    completionRatio: 0,
                    interruptionCount: 0,
                    stoppedEarly: false,
                    failureReason: input.reason
                )
            }

            if let minutes = input.minutesSpent, !minutesSpentRange.contains(minutes) {
                throw OutcomeValidationError.invalidMinutesSpent
            }

            return ExecutionOutcomeRequest(
                taskStatus: OutcomeStatus.abandoned.taskStatus,
                outcomeStatus: .abandoned,
                completionRatio: 0,
                interruptionCount: nil,
                stoppedEarly: (input.minutesSpent ?? 0) > 0,
                failureReason: input.reason,
                activeMinutes: input.minutesSpent,
                actualEndUnknown: true
            )
        }
    }

    // MARK: - Logged plan revision

    /// `buildRevisionInput` from the PWA. `existing` supplies the stored
    /// times, minutes, outcome, and stopped-early flag.
    static func buildRevision(
        _ input: RevisionInput,
        existing: HabitTraceExecution,
        now: Date = .now
    ) throws -> ExecutionOutcomeRequest {
        if input.result == .notStarted {
            return ExecutionOutcomeRequest(
                taskStatus: OutcomeStatus.notStarted.taskStatus,
                outcomeStatus: .notStarted,
                completionRatio: 0,
                interruptionCount: 0,
                stoppedEarly: false,
                failureReason: input.reason
            )
        }

        if let interruptions = input.interruptions, !interruptionRange.contains(interruptions) {
            throw OutcomeValidationError.invalidInterruptions
        }

        var completionRatio: Double = 0
        if input.result == .partial {
            guard let percent = input.progressPercent, progressRange.contains(percent) else {
                throw OutcomeValidationError.invalidProgress
            }
            completionRatio = Double(percent) / 100
        } else if input.result == .completed {
            completionRatio = 1
        }

        if let minutes = input.minutesSpent, !minutesSpentRange.contains(minutes) {
            throw OutcomeValidationError.invalidMinutesSpent
        }

        for (value, label) in [(input.actualStart, "start"), (input.actualEnd, "finish")] {
            if let value, value.timeIntervalSince(now) > futureTolerance {
                throw OutcomeValidationError.timeInFuture(label)
            }
        }

        let effectiveStart = input.actualStart ?? existing.actualStartDate
        let effectiveEnd = input.actualEnd ?? existing.actualEndDate
        if let effectiveStart, let effectiveEnd {
            if effectiveEnd < effectiveStart {
                throw OutcomeValidationError.endBeforeStart
            }
            if input.result != .completed, let minutes = input.minutesSpent {
                let elapsed = Int(effectiveEnd.timeIntervalSince(effectiveStart) / 60)
                if minutes > elapsed {
                    throw OutcomeValidationError.minutesExceedElapsed
                }
            }
        }

        let stoppedEarly: Bool
        if existing.outcomeStatus == input.result {
            stoppedEarly = existing.stoppedEarly
        } else {
            stoppedEarly = input.result == .partial
                || (input.result == .abandoned && (input.minutesSpent ?? 0) > 0)
        }

        return ExecutionOutcomeRequest(
            taskStatus: input.result.taskStatus,
            outcomeStatus: input.result,
            completionRatio: completionRatio,
            interruptionCount: input.interruptions,
            stoppedEarly: stoppedEarly,
            failureReason: input.result == .completed ? nil : input.reason,
            activeMinutes: input.result == .completed ? existing.activeMinutes : input.minutesSpent,
            actualStartTime: input.actualStart,
            actualEndTime: input.actualEnd
        )
    }

    // MARK: - Confirmation text

    /// `outcomeConfirmation` from the PWA: the toast body after saving.
    static func confirmation(for request: ExecutionOutcomeRequest, scheduledEnd: String?) -> String {
        if request.taskStatus == "success" {
            if let end = request.actualEndTime {
                return "Marked completed · finished \(TaskTimeFormatting.displayTime(end))."
            }
            if let scheduledEnd {
                return "Marked completed · scheduled end \(scheduledEnd)."
            }
            return "Marked completed."
        }
        if request.outcomeStatus == .notStarted {
            return "Marked not completed · not started."
        }
        if let minutes = request.activeMinutes {
            return "Marked not completed · \(minutes) min recorded."
        }
        return "Marked not completed."
    }

    /// Confirmation text from the server's record after saving.
    static func confirmation(for execution: HabitTraceExecution, scheduledEnd: String?) -> String {
        if execution.taskStatus == "success" {
            if let end = execution.actualEndDate {
                return "Marked completed · finished \(TaskTimeFormatting.displayTime(end))."
            }
            if let scheduledEnd {
                return "Marked completed · scheduled end \(scheduledEnd)."
            }
            return "Marked completed."
        }
        if execution.outcomeStatus == .notStarted {
            return "Marked not completed · not started."
        }
        if let minutes = execution.activeMinutes {
            return "Marked not completed · \(minutes) min recorded."
        }
        return "Marked not completed."
    }

    /// The server types `idempotency_key` as a UUID. Task ids are UUIDs in
    /// production; anything else is sent without a key rather than rejected.
    static func idempotencyKey(for taskID: String) -> String? {
        UUID(uuidString: taskID) == nil ? nil : taskID
    }
}
