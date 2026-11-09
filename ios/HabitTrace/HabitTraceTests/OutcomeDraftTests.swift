import Foundation
import Testing
@testable import HabitTrace

/// The outcome sheet's state model and the inputs it hands to the builder.
struct OutcomeDraftTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func defaultsAreEmpty() {
        let draft = OutcomeDraft(activeStart: nil, now: now)
        #expect(draft.choice == nil)
        #expect(draft.canSubmit == false)
        #expect(draft.recordsFinishTime == false)
        #expect(draft.finishedAt == now)
        #expect(draft.isActive == false)
    }

    @Test func completedCarriesFinishOnlyWhenRecorded() {
        var draft = OutcomeDraft(activeStart: nil, now: now)
        draft.choice = .completed
        #expect(draft.input == OutcomeInput(choice: .completed))

        draft.recordsFinishTime = true
        draft.finishedAt = now.addingTimeInterval(-300)
        #expect(draft.input.finishedAt == now.addingTimeInterval(-300))
        #expect(draft.canSubmit)
    }

    @Test func notCompletedCarriesOnlyItsFields() {
        var draft = OutcomeDraft(activeStart: nil, now: now)
        draft.choice = .notCompleted
        draft.setMinutesSpentText("45")
        draft.reason = .lowReadiness
        draft.recordsFinishTime = true  // completed-only, must be ignored

        let input = draft.input
        #expect(input.choice == .notCompleted)
        #expect(input.minutesSpent == 45)
        #expect(input.reason == .lowReadiness)
        #expect(input.finishedAt == nil)
        #expect(input.didNotStart == false)
    }

    @Test func didNotStartClearsMinutesAndDropsThemFromInput() {
        var draft = OutcomeDraft(activeStart: nil, now: now)
        draft.choice = .notCompleted
        draft.setMinutesSpentText("30")
        draft.setDidNotStart(true)
        #expect(draft.minutesSpentText.isEmpty)
        #expect(draft.input.didNotStart == true)
        #expect(draft.input.minutesSpent == nil)
    }

    @Test func didNotStartIsIgnoredForActivePlans() {
        var draft = OutcomeDraft(activeStart: now.addingTimeInterval(-600), now: now)
        draft.choice = .notCompleted
        draft.setDidNotStart(true)
        #expect(draft.isActive)
        #expect(draft.input.didNotStart == false, "the option is hidden when a start is recorded")
    }

    @Test func minutesTextKeepsDigitsOnly() {
        var draft = OutcomeDraft(activeStart: nil, now: now)
        draft.setMinutesSpentText("1a2b345")
        #expect(draft.minutesSpentText == "1234")
        #expect(draft.minutesSpent == 1234)
    }

    @Test func validationComesFromTheSharedBuilder() {
        var draft = OutcomeDraft(activeStart: nil, now: now)
        #expect(draft.validationError(now: now) == OutcomeValidationError.noChoice.errorDescription)

        draft.choice = .notCompleted
        draft.setMinutesSpentText("2000")
        #expect(draft.validationError(now: now) == OutcomeValidationError.invalidMinutesSpent.errorDescription)

        draft.setMinutesSpentText("20")
        #expect(draft.validationError(now: now) == nil)

        var activeDraft = OutcomeDraft(activeStart: now.addingTimeInterval(-600), now: now)
        activeDraft.choice = .completed
        activeDraft.recordsFinishTime = true
        activeDraft.finishedAt = now.addingTimeInterval(-3600)
        #expect(activeDraft.validationError(now: now) == OutcomeValidationError.finishBeforeStart.errorDescription)
    }
}
