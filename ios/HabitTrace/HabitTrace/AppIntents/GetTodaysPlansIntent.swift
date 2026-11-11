import AppIntents
import Foundation

/// "What do I have planned today?" Reads today's plans from the backend and
/// returns them for use in Shortcuts.
struct GetTodaysPlansIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Get Today's Plans"
    nonisolated static let description = IntentDescription(
        "Tells you what you have planned in HabitTrace today.",
        categoryName: "Plans"
    )
    nonisolated static let supportedModes: IntentModes = .background

    @Dependency
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<[PlanEntity]> & ProvidesDialog {
        let service = PlanIntentService(taskService: taskService)
        let tasks = try await service.todaysPlans()
        let dialog = PlanIntentLogic.todaysPlansDialog(for: tasks)
        return .result(
            value: tasks.map(PlanEntity.init(task:)),
            dialog: IntentDialog("\(dialog)")
        )
    }
}
