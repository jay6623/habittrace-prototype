import Foundation
import Combine

/// Main-actor service over `APIClient`.
///
/// `tasks` is the shared, unfiltered task array used by Today. Plans keeps
/// its own per-date list and calls the throwing methods below; every
/// mutation reconciles the shared array by task id so Today stays correct.
@MainActor
final class TaskService: ObservableObject {
    @Published private(set) var tasks: [HabitTraceTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - Load Tasks

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

    // MARK: - Create Task

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

    // MARK: - Complete Task

    func completeTask(
        accessToken: String,
        taskId: String
    ) async {
        errorMessage = nil

        do {
            _ = try await apiClient.completeTask(
                accessToken: accessToken,
                taskId: taskId
            )

            tasks = try await apiClient.fetchTasks(
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Update Task

    func updateTask(
        accessToken: String,
        taskId: String,
        title: String,
        notes: String?,
        taskCategory: String,
        plannedStartTime: String,
        plannedDate: String?,
        plannedDurationMin: Int,
        importance: Int,
        energyLevel: Int,
        focusLevel: Int
    ) async {
        errorMessage = nil

        do {
            let updatedTask = try await apiClient.updateTask(
                accessToken: accessToken,
                taskId: taskId,
                title: title,
                notes: notes,
                taskCategory: taskCategory,
                plannedStartTime: plannedStartTime,
                plannedDate: plannedDate,
                plannedDurationMin: plannedDurationMin,
                importance: importance,
                energyLevel: energyLevel,
                focusLevel: focusLevel
            )

            if tasks.contains(where: { $0.id == taskId }) {
                upsertTask(updatedTask)
            } else {
                tasks = try await apiClient.fetchTasks(
                    accessToken: accessToken
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Task

    func deleteTask(
        accessToken: String,
        taskId: String
    ) async {
        errorMessage = nil

        do {
            try await apiClient.deleteTask(
                accessToken: accessToken,
                taskId: taskId
            )

            removeTask(id: taskId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Throwing task operations (Plans)

    /// Loads one day's tasks and reconciles them into the shared array.
    /// The result is unsorted; the caller sorts by parsed start time.
    func fetchTasks(accessToken: String, on date: String) async throws -> [HabitTraceTask] {
        let fetched = try await apiClient.fetchTasks(accessToken: accessToken, date: date)
        replaceTasks(on: date, with: fetched)
        return fetched
    }

    /// Creates a task and returns it; errors propagate to the caller.
    func addTask(
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
    ) async throws -> HabitTraceTask {
        let created = try await apiClient.createTask(
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

        upsertTask(created)
        return created
    }

    /// Updates a task and returns it; errors propagate to the caller.
    func editTask(
        accessToken: String,
        taskId: String,
        title: String,
        notes: String?,
        taskCategory: String,
        plannedStartTime: String,
        plannedDate: String?,
        plannedDurationMin: Int,
        importance: Int,
        energyLevel: Int,
        focusLevel: Int
    ) async throws -> HabitTraceTask {
        let updated = try await apiClient.updateTask(
            accessToken: accessToken,
            taskId: taskId,
            title: title,
            notes: notes,
            taskCategory: taskCategory,
            plannedStartTime: plannedStartTime,
            plannedDate: plannedDate,
            plannedDurationMin: plannedDurationMin,
            importance: importance,
            energyLevel: energyLevel,
            focusLevel: focusLevel
        )

        upsertTask(updated)
        return updated
    }

    /// Deletes a task; errors propagate to the caller.
    func removeTask(accessToken: String, taskId: String) async throws {
        try await apiClient.deleteTask(accessToken: accessToken, taskId: taskId)
        removeTask(id: taskId)
    }

    // MARK: - Executions (Plans)

    /// Executions that have started but not finished, newest first.
    func fetchActiveExecutions(accessToken: String) async throws -> [HabitTraceExecution] {
        try await apiClient.fetchExecutions(accessToken: accessToken, activeOnly: true)
    }

    /// All of the user's executions, newest first.
    func fetchExecutions(accessToken: String) async throws -> [HabitTraceExecution] {
        try await apiClient.fetchExecutions(accessToken: accessToken)
    }

    func startExecution(accessToken: String, taskId: String) async throws -> HabitTraceExecution {
        try await apiClient.startExecution(accessToken: accessToken, taskId: taskId)
    }

    /// Records a finished outcome in one call and reconciles the task's
    /// status locally. Use the task id as `idempotencyKey` to log once.
    func logExecution(
        accessToken: String,
        taskId: String,
        outcome: ExecutionOutcomeRequest,
        idempotencyKey: String?
    ) async throws -> HabitTraceExecution {
        let execution = try await apiClient.logExecution(
            accessToken: accessToken,
            taskId: taskId,
            outcome: outcome,
            idempotencyKey: idempotencyKey
        )

        applyStatus(from: execution)
        return execution
    }

    /// Finishes an active execution and reconciles the task's status.
    func completeExecution(
        accessToken: String,
        executionId: String,
        outcome: ExecutionOutcomeRequest
    ) async throws -> HabitTraceExecution {
        let execution = try await apiClient.completeExecution(
            accessToken: accessToken,
            executionId: executionId,
            outcome: outcome
        )

        applyStatus(from: execution)
        return execution
    }

    /// Revises a finished execution and reconciles the task's status.
    func reviseExecution(
        accessToken: String,
        executionId: String,
        outcome: ExecutionOutcomeRequest
    ) async throws -> HabitTraceExecution {
        let execution = try await apiClient.reviseExecution(
            accessToken: accessToken,
            executionId: executionId,
            outcome: outcome
        )

        applyStatus(from: execution)
        return execution
    }

    // MARK: - Reconciliation

    /// Inserts or replaces a task in the shared array by id.
    func upsertTask(_ task: HabitTraceTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    /// Removes a task from the shared array by id.
    func removeTask(id: String) {
        tasks.removeAll { $0.id == id }
    }

    /// Replaces every shared task planned on `date` with `fetched`,
    /// leaving other days untouched.
    func replaceTasks(on date: String, with fetched: [HabitTraceTask]) {
        let fetchedIDs = Set(fetched.map(\.id))
        tasks.removeAll { $0.plannedDate == date || fetchedIDs.contains($0.id) }
        tasks.append(contentsOf: fetched)
    }

    /// Mirrors the server's task-status sync after an execution write so
    /// Today reflects it without a full reload.
    private func applyStatus(from execution: HabitTraceExecution) {
        guard
            let status = execution.taskStatus,
            let index = tasks.firstIndex(where: { $0.id == execution.taskId })
        else {
            return
        }

        tasks[index] = tasks[index].replacingStatus(status)
    }

    /// Public hook so feature view models can mirror a status change into
    /// the shared array without reloading.
    func applyTaskStatus(_ status: String, toTaskID taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index] = tasks[index].replacingStatus(status)
    }
}
