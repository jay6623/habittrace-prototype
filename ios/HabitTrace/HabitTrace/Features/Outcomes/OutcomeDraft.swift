import Foundation

/// UI state for the outcome sheet, kept free of SwiftUI so it can be
/// tested. Mirrors the PWA's `OutcomeDraft`: a choice between Completed
/// and Not completed, each with optional details.
struct OutcomeDraft: Equatable {
    /// The recorded start of an active execution, if any. When present the
    /// "I didn't start" option is hidden and the finish must follow it.
    let activeStart: Date?

    var choice: OutcomeChoice?
    /// Completed: whether the user chose to record a finish time at all.
    var recordsFinishTime = false
    var finishedAt: Date
    /// Not completed.
    var didNotStart = false
    var minutesSpentText = ""
    var reason: FailureReason?

    init(activeStart: Date?, now: Date = .now) {
        self.activeStart = activeStart
        finishedAt = now
    }

    var isActive: Bool {
        activeStart != nil
    }

    var minutesSpent: Int? {
        Int(minutesSpentText)
    }

    /// What the sheet would submit for the current selections. Only the
    /// fields of the chosen option are carried, as in the PWA.
    var input: OutcomeInput {
        switch choice {
        case .completed:
            OutcomeInput(choice: .completed, finishedAt: recordsFinishTime ? finishedAt : nil)
        case .notCompleted:
            OutcomeInput(
                choice: .notCompleted,
                didNotStart: didNotStart && !isActive,
                minutesSpent: didNotStart ? nil : minutesSpent,
                reason: reason
            )
        case nil:
            OutcomeInput()
        }
    }

    /// First rule the input would break, from the shared builder, or nil.
    func validationError(now: Date = .now) -> String? {
        do {
            _ = try OutcomeRequestBuilder.buildRequest(input, activeStart: activeStart, now: now)
            return nil
        } catch {
            return ErrorPresentation.message(for: error)
        }
    }

    var canSubmit: Bool {
        choice != nil
    }

    /// Digits only, at most four characters.
    mutating func setMinutesSpentText(_ text: String) {
        minutesSpentText = String(text.filter(\.isNumber).prefix(4))
    }

    /// Toggling "I didn't start" clears minutes, as in the PWA.
    mutating func setDidNotStart(_ value: Bool) {
        didNotStart = value
        if value {
            minutesSpentText = ""
        }
    }
}
