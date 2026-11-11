import Combine
import Foundation

/// State for "Generate day": the task form, the generated draft, time
/// adjustments, and confirmation. Mirrors `/dashboard/scheduler/generate`.
@MainActor
final class GenerateDayViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String

    @Published var form: GenerateDayForm
    @Published private(set) var result: GeneratedDaySchedule?
    @Published private(set) var isBusy = false
    @Published private(set) var savingTaskID: String?
    @Published private(set) var errorMessage: String?
    @Published var toast: HTToastMessage?

    private let taskService: TaskService
    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider
    private let draftID: String?
    private let timezoneName: String
    private var didLoadDraft = false

    init(
        taskService: TaskService,
        apiClient: APIClient = APIClient(),
        accessTokenProvider: @escaping AccessTokenProvider,
        preferences: PlanningPreferences,
        initialDate: Date = .now,
        draftID: String? = nil,
        timezoneName: String = TimeZone.current.identifier
    ) {
        self.taskService = taskService
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.draftID = draftID
        self.timezoneName = timezoneName
        self.form = GenerateDayForm(
            dateKey: SchedulerLogic.dateKey(initialDate),
            dayStart: preferences.workStart,
            dayEnd: preferences.workEnd
        )
    }

    var schedule: DailySchedule? { result?.schedule }
    var isDraft: Bool { result?.isDraft ?? false }
    var canConfirm: Bool { isDraft && !isBusy && !(schedule?.scheduledTasks.isEmpty ?? true) }
    /// True while a deep-linked draft is being fetched and nothing is shown yet.
    var isLoadingDraft: Bool { draftID != nil && result == nil && isBusy }

    // MARK: - Draft loading

    /// Loads the draft named by `draftID` once (deep links from the coach).
    func loadDraftIfNeeded() async {
        guard let draftID, !didLoadDraft else { return }
        didLoadDraft = true
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let token = try await accessTokenProvider()
            result = try await apiClient.fetchDailySchedule(accessToken: token, scheduleID: draftID)
        } catch {
            errorMessage = Self.message(for: error, fallback: "We couldn't load this daily plan draft.")
        }
    }

    // MARK: - Form editing

    func addTask() {
        form.tasks.append(GenerateDayTaskDraft())
    }

    func removeTask(id: UUID) {
        guard form.tasks.count > 1 else { return }
        form.tasks.removeAll { $0.id == id }
    }

    // MARK: - Generate

    func generate() async {
        guard !isBusy else { return }
        errorMessage = nil
        if let validation = form.validationError {
            errorMessage = validation
            return
        }
        guard let request = form.makeRequest(timezoneName: timezoneName) else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            let token = try await accessTokenProvider()
            result = try await apiClient.generateDailySchedule(accessToken: token, request: request)
            toast = .success("Draft schedule generated. Review and adjust it before confirming.")
        } catch {
            errorMessage = Self.message(for: error, fallback: "We couldn't generate a schedule. Check the backend connection and try again.")
        }
    }

    // MARK: - Adjust

    /// Moves one drafted task to `minutes` after midnight on the draft's day.
    func moveTask(taskID: String, toMinutes minutes: Int) async {
        guard let result, result.isDraft, savingTaskID == nil,
              let scheduledStart = SchedulerLogic.isoTimestamp(dateKey: result.schedule.selectedDate, minutes: minutes)
        else { return }

        savingTaskID = taskID
        errorMessage = nil
        defer { savingTaskID = nil }
        do {
            let token = try await accessTokenProvider()
            self.result = try await apiClient.updateDailySchedule(
                accessToken: token,
                scheduleID: result.schedule.id,
                adjustments: [DailyScheduleAdjustment(taskId: taskID, scheduledStart: scheduledStart)]
            )
            toast = .success("Draft time updated")
        } catch {
            errorMessage = Self.message(for: error, fallback: "That time could not be saved. It may overlap another plan or buffer.")
        }
    }

    // MARK: - Confirm

    func confirm() async {
        guard let result, result.isDraft, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let token = try await accessTokenProvider()
            let confirmed = try await apiClient.confirmDailySchedule(accessToken: token, scheduleID: result.schedule.id)
            self.result = GeneratedDaySchedule(schedule: confirmed, meta: result.meta)
            toast = .success("Daily plan confirmed. The scheduled tasks are now in HabitTrace.")
            await taskService.loadTasks(accessToken: token)
        } catch {
            errorMessage = Self.message(for: error, fallback: "The draft could not be confirmed. No draft changes were lost.")
        }
    }

    func startNewDraft() {
        result = nil
        errorMessage = nil
    }

    // MARK: - Helpers

    /// Backend `detail` text when present (the PWA's `ApiError.detail`),
    /// else the page's fallback sentence.
    nonisolated static func message(for error: Error, fallback: String) -> String {
        if case .httpStatus(_, let detail?) = error as? APIError, !detail.isEmpty {
            return detail
        }
        return fallback
    }
}
