import Foundation

/// UI state for the outcome sheet, kept free of SwiftUI so it can be
/// tested. Mirrors the PWA's `OutcomeSheet` state: a two-step flow where
/// Partly completed and Not this time ask for a reason, plus the shared
/// interruption count and, for plans that were never started, the actual
/// start and finish times.
struct OutcomeDraft: Equatable {
    /// Results that need a failure reason before they can be saved.
    nonisolated enum ReasonChoice: Equatable, Sendable {
        case partial
        case abandoned

        var title: String {
            switch self {
            case .partial: "Partly completed"
            case .abandoned: "Not this time"
            }
        }
    }

    nonisolated enum Step: Equatable, Sendable {
        case choose
        case reason(ReasonChoice)
    }

    /// True when the plan has a server-recorded start. Times are then
    /// omitted and "I didn't start this plan" is not offered.
    let isActive: Bool
    var step: Step = .choose
    var interruptionCount = 0
    var selectedReason: FailureReason?
    /// Digits typed into "How much did you complete? (%)".
    var completionPercentText = ""
    var actualStart: Date
    var actualEnd: Date

    /// Seeds defaults the way the PWA does: finish defaults to now. The
    /// PWA leaves start empty; a native picker needs a value, so start
    /// defaults to the planned start when it is in the past, otherwise
    /// the planned duration before the finish time.
    init(
        task: HabitTraceTask,
        activeExecution: HabitTraceExecution?,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        isActive = activeExecution != nil
        actualEnd = now

        let plannedStart = TaskTimeFormatting.plannedStart(
            date: task.plannedDate,
            time: task.plannedStartTime
        )
        let duration = TimeInterval(task.plannedDurationMin ?? 30) * 60

        if let plannedStart, plannedStart <= now {
            actualStart = plannedStart
        } else {
            actualStart = now.addingTimeInterval(-duration)
        }
    }

    init(isActive: Bool, actualStart: Date, actualEnd: Date) {
        self.isActive = isActive
        self.actualStart = actualStart
        self.actualEnd = actualEnd
    }

    // MARK: - Derived

    var completionPercent: Int? {
        Int(completionPercentText)
    }

    /// Whether "I didn't start this plan" applies, as in the PWA.
    var offersNotStarted: Bool {
        !isActive && step == .choose
    }

    /// The result the reason step will save, if the sheet is on that step.
    var reasonStepResult: OutcomeResult? {
        switch step {
        case .choose: nil
        case .reason(.partial): .partial(percent: completionPercent ?? 0)
        case .reason(.abandoned): .abandoned
        }
    }

    /// Builds the submission input for a result. Times are included only
    /// for unstarted plans and only for outcomes that can carry them.
    func input(for result: OutcomeResult) -> OutcomeInput {
        let carriesTimes: Bool
        switch result {
        case .notStarted, .stillWorking: carriesTimes = false
        default: carriesTimes = !isActive
        }

        return OutcomeInput(
            result: result,
            failureReason: selectedReason,
            interruptionCount: result == .notStarted ? 0 : interruptionCount,
            actualStart: carriesTimes ? actualStart : nil,
            actualEnd: carriesTimes ? actualEnd : nil
        )
    }

    /// First rule the input would break, from the shared builder, or nil.
    func validationError(
        for result: OutcomeResult,
        taskID: String,
        activeExecution: HabitTraceExecution?,
        now: Date = .now
    ) -> String? {
        do {
            _ = try OutcomeRequestBuilder.build(
                input(for: result),
                taskID: taskID,
                activeExecution: activeExecution,
                now: now
            )
            return nil
        } catch {
            return ErrorPresentation.message(for: error)
        }
    }

    /// Whether the reason step has enough to save.
    func canSaveReasonStep(taskID: String, activeExecution: HabitTraceExecution?, now: Date = .now) -> Bool {
        guard let result = reasonStepResult, selectedReason != nil else { return false }
        return validationError(for: result, taskID: taskID, activeExecution: activeExecution, now: now) == nil
    }

    // MARK: - Transitions

    mutating func choose(_ choice: ReasonChoice) {
        step = .reason(choice)
        selectedReason = nil
        completionPercentText = ""
    }

    mutating func goBack() {
        step = .choose
        selectedReason = nil
        completionPercentText = ""
    }

    /// Keeps the percent field to at most two digits.
    mutating func setCompletionPercentText(_ text: String) {
        completionPercentText = String(text.filter(\.isNumber).prefix(2))
    }
}
