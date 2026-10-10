import Foundation
import Combine

/// State for the Plans screen.
///
/// Owns the date-scoped task list and the active-execution map. It never
/// uses `TaskService.tasks` as its source of truth; the service reconciles
/// that shared array for Today as a side effect of the calls made here.
/// Networking stays behind `TaskService`, and the access token comes from
/// an injected provider so the model can be driven without `AuthManager`.
@MainActor
final class PlansViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String

    // MARK: - Published state

    /// Start of the selected day in the current calendar.
    @Published private(set) var selectedDate: Date
    @Published var selectedFilter: PlansFilter = .all
    /// Tasks planned on `selectedDate`, sorted by `PlanOrdering`.
    @Published private(set) var tasks: [HabitTraceTask] = []
    /// Active execution per task id, across all dates.
    @Published private(set) var activeExecutions: [String: HabitTraceExecution] = [:]
    @Published private(set) var isLoading = false
    /// True while a mutation is in flight. Gates every action.
    @Published private(set) var isBusy = false
    /// Presentable failure from the last load, cleared on success.
    @Published private(set) var loadErrorMessage: String?
    /// Presentable failure from the last mutation. The UI clears it.
    @Published var actionErrorMessage: String?

    // MARK: - Dependencies

    private let taskService: TaskService
    private let accessToken: AccessTokenProvider
    private let calendar: Calendar
    private let now: () -> Date

    private var requestGeneration = 0
    private var loadTask: Task<Void, Never>?

    init(
        taskService: TaskService,
        accessTokenProvider: @escaping AccessTokenProvider,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.taskService = taskService
        self.accessToken = accessTokenProvider
        self.calendar = calendar
        self.now = now
        selectedDate = calendar.startOfDay(for: now())
    }

    // MARK: - Derived state

    /// Stored `"yyyy-MM-dd"` key for the selected day.
    var selectedDateKey: String {
        TaskTimeFormatting.isoDate(from: selectedDate)
    }

    var isShowingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: now())
    }

    /// Every plan on the selected day joined with its active execution.
    var items: [PlanListItem] {
        tasks.map { PlanListItem(task: $0, activeExecution: activeExecutions[$0.id]) }
    }

    /// Plans that pass `selectedFilter`.
    var filteredItems: [PlanListItem] {
        items.filter { selectedFilter.includes($0.status) }
    }

    /// Computed over all plans on the day, never the filtered subset.
    var summary: PlansSummary {
        PlansSummary(items: items)
    }

    /// Non-nil when the list has nothing to show and no load is pending.
    var emptyState: PlansEmptyState? {
        guard !isLoading, loadErrorMessage == nil else { return nil }
        if tasks.isEmpty { return .noPlans }
        if filteredItems.isEmpty { return .noMatches }
        return nil
    }

    func item(for taskID: String) -> PlanListItem? {
        items.first { $0.id == taskID }
    }

    func isRunning(_ taskID: String) -> Bool {
        activeExecutions[taskID] != nil
    }

    func activeExecution(for taskID: String) -> HabitTraceExecution? {
        activeExecutions[taskID]
    }

    // MARK: - Date navigation

    func showPreviousDay() {
        shift(days: -1)
    }

    func showNextDay() {
        shift(days: 1)
    }

    func showToday() {
        select(date: now())
    }

    /// Selects a day and loads it. No-op when the day is already selected.
    func select(date: Date) {
        let day = calendar.startOfDay(for: date)
        guard day != selectedDate else { return }
        selectedDate = day
        startLoad()
    }

    private func shift(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        select(date: next)
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load()
        }
    }

    // MARK: - Loading

    /// Loads the selected day's tasks and the active executions.
    ///
    /// Each call bumps a generation counter; results are applied only if
    /// no newer load started while this one was waiting, so a slow
    /// response for an old date can never overwrite a newer selection.
    func load() async {
        requestGeneration += 1
        let generation = requestGeneration
        let dateKey = selectedDateKey

        isLoading = true
        loadErrorMessage = nil

        do {
            let token = try await accessToken()
            let fetchedTasks = try await taskService.fetchTasks(accessToken: token, on: dateKey)
            let fetchedActive = try await taskService.fetchActiveExecutions(accessToken: token)

            guard generation == requestGeneration else { return }

            tasks = PlanOrdering.sorted(fetchedTasks)
            activeExecutions = Self.activeMap(fetchedActive)
            isLoading = false
        } catch {
            guard generation == requestGeneration else { return }

            tasks = []
            loadErrorMessage = Self.presentableMessage(for: error)
            isLoading = false
        }
    }

    /// Reloads only the active-execution map, for cheap refreshes.
    func refreshActiveExecutions() async {
        do {
            let token = try await accessToken()
            activeExecutions = Self.activeMap(try await taskService.fetchActiveExecutions(accessToken: token))
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
        }
    }

    // MARK: - Overlap detection

    /// Plans that would overlap the draft, using a fresh fetch of the
    /// draft's day as the PWA does. Throws if that fetch fails, in which
    /// case the caller must not save.
    func overlappingPlans(for draft: PlanDraft, excludingTaskID: String? = nil) async throws -> [HabitTraceTask] {
        let token = try await accessToken()
        let dayTasks = try await taskService.fetchTasks(accessToken: token, on: draft.dateKey)

        // The fresh fetch doubles as a refresh when it is the visible day.
        if draft.dateKey == selectedDateKey {
            tasks = PlanOrdering.sorted(dayTasks)
        }

        return PlanOverlap.conflicts(
            for: draft.overlapCandidate,
            among: dayTasks,
            excludingTaskID: excludingTaskID
        )
    }

    // MARK: - Mutations

    /// Creates a plan. If it lands on another day, that day is selected
    /// and loaded, as the PWA does.
    @discardableResult
    func createPlan(from draft: PlanDraft) async -> HabitTraceTask? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        if let message = draft.validationError {
            actionErrorMessage = message
            return nil
        }

        do {
            let token = try await accessToken()
            let existingCount = try await countOfTasks(on: draft.dateKey, token: token)

            let created = try await taskService.addTask(
                accessToken: token,
                title: draft.trimmedTitle,
                notes: draft.normalizedNotes,
                taskCategory: draft.category.rawValue,
                plannedStartTime: draft.storedStartTime,
                plannedDate: draft.dateKey,
                plannedDurationMin: draft.durationMinutes,
                importance: draft.importance,
                energyLevel: 3,
                focusLevel: 3,
                totalTasksToday: max(1, existingCount + 1)
            )

            reconcile(created)
            return created
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// Updates a pending plan's planning fields. Energy and focus are
    /// preserved from the existing task, as the PWA does.
    @discardableResult
    func updatePlan(taskID: String, with draft: PlanDraft) async -> HabitTraceTask? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        if let message = draft.validationError {
            actionErrorMessage = message
            return nil
        }

        let existing = tasks.first { $0.id == taskID }

        do {
            let token = try await accessToken()

            let updated = try await taskService.editTask(
                accessToken: token,
                taskId: taskID,
                title: draft.trimmedTitle,
                notes: draft.normalizedNotes,
                taskCategory: draft.category.rawValue,
                plannedStartTime: draft.storedStartTime,
                plannedDate: draft.dateKey,
                plannedDurationMin: draft.durationMinutes,
                importance: draft.importance,
                energyLevel: existing?.energyLevel ?? 3,
                focusLevel: existing?.focusLevel ?? 3
            )

            reconcile(updated)
            return updated
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// Deletes a plan and its execution records on the server.
    @discardableResult
    func deletePlan(taskID: String) async -> Bool {
        guard beginMutation() else { return false }
        defer { endMutation() }

        do {
            let token = try await accessToken()
            try await taskService.removeTask(accessToken: token, taskId: taskID)
            tasks.removeAll { $0.id == taskID }
            activeExecutions[taskID] = nil
            return true
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return false
        }
    }

    /// Starts a plan. Idempotent on the server; also used for the
    /// outcome sheet's "Still working" choice.
    @discardableResult
    func startPlan(taskID: String) async -> HabitTraceExecution? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        do {
            let token = try await accessToken()
            let execution = try await taskService.startExecution(accessToken: token, taskId: taskID)
            activeExecutions[taskID] = execution
            return execution
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// Records a finished outcome the way the PWA does: completes the
    /// active execution if there is one, otherwise logs a new execution
    /// keyed by the task id so repeated taps cannot double-log.
    @discardableResult
    func recordOutcome(taskID: String, outcome: ExecutionOutcomeRequest) async -> HabitTraceExecution? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        do {
            let token = try await accessToken()
            let execution: HabitTraceExecution

            if let active = activeExecutions[taskID] {
                execution = try await taskService.completeExecution(
                    accessToken: token,
                    executionId: active.id,
                    outcome: outcome
                )
            } else {
                execution = try await taskService.logExecution(
                    accessToken: token,
                    taskId: taskID,
                    outcome: outcome,
                    idempotencyKey: taskID
                )
            }

            applyFinished(execution)
            return execution
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// Completes a specific active execution.
    @discardableResult
    func completeExecution(executionID: String, outcome: ExecutionOutcomeRequest) async -> HabitTraceExecution? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        do {
            let token = try await accessToken()
            let execution = try await taskService.completeExecution(
                accessToken: token,
                executionId: executionID,
                outcome: outcome
            )
            applyFinished(execution)
            return execution
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// Revises an already finished execution (logged plan editing).
    @discardableResult
    func reviseExecution(executionID: String, outcome: ExecutionOutcomeRequest) async -> HabitTraceExecution? {
        guard beginMutation() else { return nil }
        defer { endMutation() }

        do {
            let token = try await accessToken()
            let execution = try await taskService.reviseExecution(
                accessToken: token,
                executionId: executionID,
                outcome: outcome
            )
            applyFinished(execution)
            return execution
        } catch {
            actionErrorMessage = Self.presentableMessage(for: error)
            return nil
        }
    }

    /// The newest finished execution for a task, for logged plan editing.
    /// Executions arrive newest first from the server.
    func latestFinishedExecution(for taskID: String) async throws -> HabitTraceExecution? {
        let token = try await accessToken()
        let executions = try await taskService.fetchExecutions(accessToken: token)
        return executions.first { $0.taskId == taskID && $0.taskStatus != nil }
    }

    // MARK: - Reconciliation

    /// Places a created or updated task: into the list if it belongs to
    /// the selected day, otherwise out of the list and onto its own day.
    private func reconcile(_ task: HabitTraceTask) {
        if task.plannedDate == selectedDateKey {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.append(task)
            }
            tasks = PlanOrdering.sorted(tasks)
            return
        }

        tasks.removeAll { $0.id == task.id }

        if let dateKey = task.plannedDate, let date = TaskTimeFormatting.date(fromISODate: dateKey) {
            select(date: date)
        }
    }

    /// Applies a finished execution: clears the active entry and mirrors
    /// the server's task-status sync locally and into the shared array.
    private func applyFinished(_ execution: HabitTraceExecution) {
        activeExecutions[execution.taskId] = nil

        guard let status = execution.taskStatus else { return }

        if let index = tasks.firstIndex(where: { $0.id == execution.taskId }) {
            tasks[index] = tasks[index].replacingStatus(status)
        }
        taskService.applyTaskStatus(status, toTaskID: execution.taskId)
    }

    private func countOfTasks(on dateKey: String, token: String) async throws -> Int {
        if dateKey == selectedDateKey {
            return tasks.count
        }
        return try await taskService.fetchTasks(accessToken: token, on: dateKey).count
    }

    private func beginMutation() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        actionErrorMessage = nil
        return true
    }

    private func endMutation() {
        isBusy = false
    }

    private static func activeMap(_ executions: [HabitTraceExecution]) -> [String: HabitTraceExecution] {
        // Newest first; keep the first entry per task.
        Dictionary(executions.map { ($0.taskId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Errors

    /// A message suitable for the UI. Backend `detail` text is kept
    /// because it carries validation rules such as "Completed tasks
    /// cannot be started"; transport failures get plain wording.
    static func presentableMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpStatus(let code, let detail):
                if let detail, !detail.isEmpty {
                    return detail
                }
                switch code {
                case 401: return "Your session has expired. Sign in again."
                case 404: return "This plan no longer exists."
                case 500...599: return "The server had a problem. Please try again."
                default: return "The request failed (HTTP \(code))."
                }
            case .invalidResponse:
                return "The server returned an unexpected response."
            case .decoding:
                return "The server response couldn't be read."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut:
                return "You're offline or the server can't be reached."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
