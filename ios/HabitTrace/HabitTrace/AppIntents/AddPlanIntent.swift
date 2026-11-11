import AppIntents
import Foundation

/// Category choices for Siri. Raw values are the stored `task_category`
/// strings and are a persisted contract: never rename or reorder them.
nonisolated enum PlanCategoryOption: String, AppEnum {
    case study = "Study"
    case work = "Work"
    case chores = "Chores"
    case fitnessHealth = "Fitness/Health"
    case errandsAdmin = "Errands/Admin"
    case hobbiesLeisure = "Hobbies/Leisure"
    case social = "Social"
    case other = "Other"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")

    static let caseDisplayRepresentations: [PlanCategoryOption: DisplayRepresentation] = [
        .study: "Study",
        .work: "Work",
        .chores: "Chores",
        .fitnessHealth: "Fitness & Health",
        .errandsAdmin: "Errands & Admin",
        .hobbiesLeisure: "Hobbies & Leisure",
        .social: "Social",
        .other: "Other",
    ]

    var taskCategory: TaskCategory {
        TaskCategory(rawValue: rawValue) ?? .other
    }
}

/// "Add a plan": creates a task through the same service the app uses.
///
/// Siri cannot put free-form speech into separate parameters, so the whole
/// answer to "What would you like to plan?" arrives in `planTitle`. The
/// intent parses it, asks for anything still missing, reads back what it
/// understood, and only then writes. Structured parameters from Shortcuts
/// always win over the parsed sentence. Runs in the background; the
/// duplicate check makes a retried run safe.
struct AddPlanIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Add a Plan"
    nonisolated static let description = IntentDescription(
        "Creates a new plan in HabitTrace. Say the title, time, and length in one sentence, such as “Study algorithms at 5 PM for 20 minutes”.",
        categoryName: "Plans"
    )
    nonisolated static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Plan",
        requestValueDialog: "What would you like to plan? You can include the time and how long it takes."
    )
    var planTitle: String

    @Parameter(title: "Start time", kind: .dateTime, requestValueDialog: "What time should it start?")
    var startTime: Date?

    @Parameter(title: "Duration (minutes)", requestValueDialog: "How many minutes should it take?")
    var durationMinutes: Int?

    @Parameter(title: "Category", requestDisambiguationDialog: "Which category?")
    var category: PlanCategoryOption?

    nonisolated static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$planTitle) at \(\.$startTime)") {
            \.$durationMinutes
            \.$category
        }
    }

    @Dependency
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<PlanEntity> & ProvidesDialog {
        let now = Date()
        var request = PlanRequestResolver.resolve(
            utterance: planTitle,
            explicitStart: startTime,
            explicitDuration: durationMinutes,
            explicitCategory: category?.taskCategory,
            now: now
        )

        // Every question is asked inline so the fields already read from
        // the sentence survive. Nothing is written until all are answered.
        if request.needsTitle {
            let answer = try await $planTitle.requestValue(IntentDialog("\(request.titlePrompt)"))
            request.apply(title: answer)
            guard !request.needsTitle else { throw PlanIntentError.emptyTitle }
        }

        if request.needsStartTime {
            let answer: Date? = try await $startTime.requestValue(IntentDialog("\(request.startTimePrompt)"))
            guard let answer else { throw PlanIntentError.missingStartTime }
            request.apply(startDate: answer, now: now)
        }

        if !request.durationIsValid {
            let answer: Int? = try await $durationMinutes.requestValue(IntentDialog("\(request.durationPrompt)"))
            guard let answer else { throw PlanIntentError.invalidDuration }
            request.apply(durationMinutes: answer)
            guard request.durationIsValid else { throw PlanIntentError.invalidDuration }
        }

        if request.needsConfirmation {
            // A cancel throws here and nothing is saved.
            try await requestConfirmation(
                actionName: .add,
                dialog: IntentDialog("\(request.confirmationText(now: now))")
            )
        }

        guard let start = request.start() else { throw PlanIntentError.missingStartTime }

        let service = PlanIntentService(taskService: taskService)
        let result = try await service.addPlan(
            title: request.title,
            start: start,
            durationMinutes: request.durationMinutes,
            category: request.category
        )

        switch result {
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
