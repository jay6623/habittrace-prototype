import AppIntents
import Foundation

/// A plan as Siri and Shortcuts see it. `id` is the server task id, which
/// is stable across launches and devices.
struct PlanEntity: AppEntity {
    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Plan")
    nonisolated static let defaultQuery = PlanEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Date")
    var plannedDate: String

    @Property(title: "Start time")
    var startTime: String

    @Property(title: "Duration (minutes)")
    var durationMinutes: Int

    @Property(title: "Category")
    var category: String

    @Property(title: "Status")
    var status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(startTime) · \(category)"
        )
    }

    @MainActor
    init(task: HabitTraceTask) {
        id = task.id
        title = task.title
        plannedDate = task.plannedDate ?? ""
        startTime = task.plannedStartTime.map(TaskTimeFormatting.displayTime) ?? ""
        durationMinutes = task.plannedDurationMin ?? 0
        category = TaskCategory.normalized(task.taskCategory).rawValue
        status = Self.statusText(task.taskStatus)
    }

    private static func statusText(_ raw: String?) -> String {
        switch raw {
        case "success": return "Completed"
        case "failed": return "Not completed"
        default: return "Planned"
        }
    }
}

/// Looks plans up by id and suggests today's plans in the Shortcuts editor.
struct PlanEntityQuery: EntityQuery {
    @Dependency
    private var taskService: TaskService

    func entities(for identifiers: [String]) async throws -> [PlanEntity] {
        let wanted = Set(identifiers)
        let service = PlanIntentService(taskService: taskService)
        let tasks = try await service.todaysPlans()
        return await MainActor.run {
            tasks.filter { wanted.contains($0.id) }.map(PlanEntity.init(task:))
        }
    }

    func suggestedEntities() async throws -> [PlanEntity] {
        let service = PlanIntentService(taskService: taskService)
        let tasks = try await service.todaysPlans()
        return await MainActor.run {
            tasks.map(PlanEntity.init(task:))
        }
    }
}
