import Foundation
import Testing
@testable import HabitTrace

/// The outcome sheet's state model: defaults, step flow, and the inputs it
/// hands to the shared builder.
struct OutcomeDraftTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private let calendar = Calendar.current

    private func task(startMinutesAgo: Int?, duration: Int = 30) -> HabitTraceTask {
        let plannedStart = startMinutesAgo.map { now.addingTimeInterval(TimeInterval(-$0 * 60)) }
        return HabitTraceTask(
            id: "8B2E4F1A-6C3D-4E5F-9A0B-1C2D3E4F5A6B",
            title: "Draft",
            notes: nil,
            taskCategory: "Work",
            plannedDate: plannedStart.map { TaskTimeFormatting.isoDate(from: $0) },
            plannedStartTime: plannedStart.map { TaskTimeFormatting.storedTime(from: $0) },
            plannedDurationMin: duration,
            importance: 3,
            energyLevel: 3,
            focusLevel: 3,
            taskStatus: "pending",
            createdAt: nil
        )
    }

    private var active: HabitTraceExecution {
        HabitTraceExecution(
            id: "exec", taskId: "t", userId: "u",
            actualStartTime: "2026-10-11T15:00:00+00:00", actualEndTime: nil,
            interruptionCount: 0, stoppedEarly: false,
            taskStatus: nil, failureReason: nil, createdAt: "c"
        )
    }

    // MARK: - Defaults

    @Test func finishDefaultsToNowAndStartToPastPlannedStart() {
        let task = task(startMinutesAgo: 90)
        let draft = OutcomeDraft(task: task, activeExecution: nil, now: now)

        #expect(draft.isActive == false)
        #expect(draft.actualEnd == now)
        // Planned start is stored to the minute, so compare at minute precision.
        let expected = now.addingTimeInterval(-90 * 60)
        #expect(abs(draft.actualStart.timeIntervalSince(expected)) < 60)
        #expect(draft.interruptionCount == 0)
        #expect(draft.step == .choose)
    }

    @Test func startDefaultsToDurationBeforeNowWhenPlanIsInTheFuture() {
        let task = task(startMinutesAgo: -120, duration: 45)
        let draft = OutcomeDraft(task: task, activeExecution: nil, now: now)
        #expect(draft.actualStart == now.addingTimeInterval(-45 * 60))
    }

    @Test func activeDraftOffersNoNotStartedOption() {
        let draft = OutcomeDraft(task: task(startMinutesAgo: 10), activeExecution: active, now: now)
        #expect(draft.isActive == true)
        #expect(draft.offersNotStarted == false)
    }

    // MARK: - Input mapping

    @Test func unstartedCompletedCarriesTimesAndInterruptions() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        draft.interruptionCount = 2
        let input = draft.input(for: .completed)
        #expect(input.actualStart == draft.actualStart)
        #expect(input.actualEnd == now)
        #expect(input.interruptionCount == 2)
    }

    @Test func activeDraftOmitsTimes() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: active, now: now)
        draft.interruptionCount = 1
        let input = draft.input(for: .completed)
        #expect(input.actualStart == nil)
        #expect(input.actualEnd == nil)
        #expect(input.interruptionCount == 1)
    }

    @Test func notStartedAndStillWorkingCarryNoTimes() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        draft.interruptionCount = 3

        let notStarted = draft.input(for: .notStarted)
        #expect(notStarted.actualStart == nil)
        #expect(notStarted.interruptionCount == 0, "the PWA zeroes interruptions for not started")

        let stillWorking = draft.input(for: .stillWorking)
        #expect(stillWorking.actualStart == nil)
    }

    // MARK: - Reason step

    @Test func choosingPartialMovesToReasonStepAndClearsSelections() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        draft.selectedReason = .other
        draft.choose(.partial)
        #expect(draft.step == .reason(.partial))
        #expect(draft.selectedReason == nil)
        #expect(draft.reasonStepResult == .partial(percent: 0))
        #expect(draft.offersNotStarted == false)
    }

    @Test func reasonStepNeedsReasonAndValidPercent() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        let taskID = task(startMinutesAgo: 60).id
        draft.choose(.partial)

        #expect(draft.canSaveReasonStep(taskID: taskID, activeExecution: nil, now: now) == false)

        draft.selectedReason = .interruption
        #expect(draft.canSaveReasonStep(taskID: taskID, activeExecution: nil, now: now) == false, "percent still missing")

        draft.setCompletionPercentText("45")
        #expect(draft.reasonStepResult == .partial(percent: 45))
        #expect(draft.canSaveReasonStep(taskID: taskID, activeExecution: nil, now: now) == true)
    }

    @Test func abandonedNeedsOnlyAReason() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        let taskID = task(startMinutesAgo: 60).id
        draft.choose(.abandoned)
        #expect(draft.canSaveReasonStep(taskID: taskID, activeExecution: nil, now: now) == false)
        draft.selectedReason = .lowReadiness
        #expect(draft.canSaveReasonStep(taskID: taskID, activeExecution: nil, now: now) == true)
        #expect(draft.input(for: .abandoned).failureReason == .lowReadiness)
    }

    @Test func percentTextKeepsAtMostTwoDigits() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        draft.setCompletionPercentText("1a23")
        #expect(draft.completionPercentText == "12")
        #expect(draft.completionPercent == 12)
    }

    @Test func goBackReturnsToChoiceStep() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        draft.choose(.abandoned)
        draft.selectedReason = .other
        draft.goBack()
        #expect(draft.step == .choose)
        #expect(draft.selectedReason == nil)
        #expect(draft.reasonStepResult == nil)
    }

    // MARK: - Validation passthrough

    @Test func validationMessagesComeFromTheSharedBuilder() {
        var draft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: nil, now: now)
        let taskID = task(startMinutesAgo: 60).id

        // End before start on an unstarted plan.
        draft.actualStart = now
        draft.actualEnd = now.addingTimeInterval(-60)
        #expect(
            draft.validationError(for: .completed, taskID: taskID, activeExecution: nil, now: now)
                == OutcomeValidationError.endBeforeStart.errorDescription
        )

        // Not started while active is refused.
        let activeDraft = OutcomeDraft(task: task(startMinutesAgo: 60), activeExecution: active, now: now)
        #expect(
            activeDraft.validationError(for: .notStarted, taskID: taskID, activeExecution: active, now: now)
                == OutcomeValidationError.notStartedWhileActive.errorDescription
        )

        // A valid completed outcome on an active plan has no error.
        #expect(activeDraft.validationError(for: .completed, taskID: taskID, activeExecution: active, now: now) == nil)
    }
}
