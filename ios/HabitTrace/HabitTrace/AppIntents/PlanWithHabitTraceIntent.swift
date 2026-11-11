import AppIntents
import Foundation

/// "Plan with HabitTrace": one spoken or dictated sentence becomes a plan.
///
/// Siri does not split free-form speech into separate parameters, so this
/// intent takes the whole sentence in a single `request` parameter, whether
/// from Siri's question or from a Dictate Text action in Shortcuts. The
/// sentence is parsed into title, day, time, duration, and category;
/// anything missing is asked for; the interpretation is read back for
/// confirmation; only then is the plan saved. `AddPlanIntent` keeps its
/// structured parameters for Shortcuts automations and is unchanged.
struct PlanWithHabitTraceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Plan with HabitTrace"
    nonisolated static let description = IntentDescription(
        "Describe a plan in one sentence, such as “Study algorithms at 5 PM for 20 minutes”. HabitTrace works out the title, time, length, and category, then confirms before saving.",
        categoryName: "Plans",
        searchKeywords: ["plan", "schedule", "task", "dictate", "voice", "natural language"]
    )
    nonisolated static let supportedModes: IntentModes = .background

    /// The complete request. Its default input connection behaviour lets
    /// Shortcuts feed it the output of a preceding action such as Dictate
    /// Text.
    @Parameter(
        title: "Request",
        description: "What to plan, in one sentence. Include the day, time, and how long it takes, for example “Workout tomorrow morning for 30 minutes”.",
        requestValueDialog: "What would you like to plan? Say it in one sentence, with the time and how long it takes."
    )
    var request: String

    /// Follow-up slots. They are left out of the summary on purpose so the
    /// Shortcuts editor shows only Request; Siri fills them only when the
    /// sentence left them out.
    @Parameter(title: "Start time", kind: .dateTime, requestValueDialog: "What time should it start?")
    var startTime: Date?

    @Parameter(title: "Duration (minutes)", requestValueDialog: "How many minutes should it take?")
    var durationMinutes: Int?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Plan \(\.$request)")
    }

    @Dependency
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<PlanEntity> & ProvidesDialog {
        let conversation = PlanConversation(
            askTitle: { prompt in
                try await $request.requestValue(IntentDialog("\(prompt)"))
            },
            askStartTime: { prompt in
                try await $startTime.requestValue(IntentDialog("\(prompt)"))
            },
            askDuration: { prompt in
                try await $durationMinutes.requestValue(IntentDialog("\(prompt)"))
            },
            confirm: { summary in
                // A cancel throws here and nothing is saved.
                try await requestConfirmation(actionName: .add, dialog: IntentDialog("\(summary)"))
            }
        )

        let service = PlanIntentService(taskService: taskService)
        let outcome = try await NaturalLanguagePlanFlow.run(
            request: request,
            now: Date(),
            conversation: conversation,
            service: service
        )

        switch outcome.result {
        case .created(let task):
            return .result(
                value: PlanEntity(task: task),
                dialog: IntentDialog("\(PlanIntentLogic.addedDialog(for: task, today: service.todayKey))")
            )
        case .duplicate(let task):
            return .result(
                value: PlanEntity(task: task),
                dialog: IntentDialog("\(PlanIntentLogic.duplicateDialog(for: task, today: service.todayKey))")
            )
        }
    }
}
