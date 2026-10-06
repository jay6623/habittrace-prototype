import Foundation
import Combine

@MainActor
final class TaskService: ObservableObject {
    @Published private(set) var tasks: [HabitTraceTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func loadTasks(accessToken: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            tasks = try await apiClient.fetchTasks(
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(
        accessToken: String,
        title: String,
        notes: String?,
        taskCategory: String,
        plannedStartTime: String,
        plannedDate: String?,
        plannedDurationMin: Int,
        importance: Int,
        energyLevel: Int,
        focusLevel: Int,
        totalTasksToday: Int
    ) async {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let createdTask = try await apiClient.createTask(
                accessToken: accessToken,
                title: title,
                notes: notes,
                taskCategory: taskCategory,
                plannedStartTime: plannedStartTime,
                plannedDate: plannedDate,
                plannedDurationMin: plannedDurationMin,
                importance: importance,
                energyLevel: energyLevel,
                focusLevel: focusLevel,
                totalTasksToday: totalTasksToday
            )

            tasks.insert(createdTask, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeTask(
        _ task: HabitTraceTask,
        accessToken: String
    ) async {
        errorMessage = nil

        do {
            _ = try await apiClient.completeTask(
                accessToken: accessToken,
                taskId: task.id
            )

            tasks = try await apiClient.fetchTasks(
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
