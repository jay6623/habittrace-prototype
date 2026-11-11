import Foundation

/// The questions a natural-language planning run may need to ask, and the
/// read-back it always performs before saving. The intent answers them
/// through Siri or Shortcuts; tests answer them from a script. `confirm`
/// throws to cancel, mirroring `requestConfirmation`.
@MainActor
struct PlanConversation {
    var askTitle: @MainActor (String) async throws -> String
    var askStartTime: @MainActor (String) async throws -> Date?
    var askDuration: @MainActor (String) async throws -> Int?
    var confirm: @MainActor (String) async throws -> Void
}

/// What a completed run interpreted and what the backend did with it.
struct NaturalLanguagePlanOutcome: Equatable {
    /// The final request, with each field tagged by where its value came
    /// from (parsed, inferred, defaulted, or answered to a question).
    let request: PlanRequest
    let result: PlanIntentService.AddResult
}

/// Turns one spoken or dictated sentence into a saved plan.
///
/// Order matters: the sentence is parsed, missing fields are asked for,
/// the interpretation is read back for confirmation, and only then is the
/// plan written through `PlanIntentService`, which also refuses duplicates.
/// Nothing is saved before the confirmation returns.
@MainActor
enum NaturalLanguagePlanFlow {
    static func run(
        request text: String,
        now: Date,
        calendar: Calendar = .current,
        defaultDuration: Int = PlanningPreferences.default.defaultDuration,
        conversation: PlanConversation,
        service: PlanIntentService
    ) async throws -> NaturalLanguagePlanOutcome {
        var request = PlanRequestResolver.resolve(
            utterance: text,
            explicitStart: nil,
            explicitDuration: nil,
            explicitCategory: nil,
            defaultDuration: defaultDuration,
            now: now,
            calendar: calendar
        )

        // Each question is asked inline so fields already read from the
        // sentence survive the follow-up.
        if request.needsTitle {
            let answer = try await conversation.askTitle(request.titlePrompt)
            request.apply(title: answer)
            guard !request.needsTitle else { throw PlanIntentError.emptyTitle }
        }

        if request.needsStartTime {
            guard let answer = try await conversation.askStartTime(request.startTimePrompt) else {
                throw PlanIntentError.missingStartTime
            }
            request.apply(startDate: answer, now: now, calendar: calendar)
        }

        if !request.durationIsValid {
            guard let answer = try await conversation.askDuration(request.durationPrompt) else {
                throw PlanIntentError.invalidDuration
            }
            request.apply(durationMinutes: answer)
            guard request.durationIsValid else { throw PlanIntentError.invalidDuration }
        }

        // A free-form sentence is always an interpretation, so it is always
        // read back. Defaults and guesses are called out in the text.
        try await conversation.confirm(request.confirmationText(now: now, calendar: calendar))

        guard let start = request.start(calendar: calendar) else { throw PlanIntentError.missingStartTime }

        let result = try await service.addPlan(
            title: request.title,
            start: start,
            durationMinutes: request.durationMinutes,
            category: request.category
        )
        return NaturalLanguagePlanOutcome(request: request, result: result)
    }
}
