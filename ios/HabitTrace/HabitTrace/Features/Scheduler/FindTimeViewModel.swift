import Combine
import Foundation

/// State for "Find a time": one day's plans, the selected plan's
/// prediction, conflict-free slots, personalized time recommendations, and
/// the daily availability editor. Mirrors `/dashboard/scheduler`.
@MainActor
final class FindTimeViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String
    /// Persists the planning preferences (see `AuthManager.saveProfile`).
    typealias PreferencesSaver = @MainActor (PlanningPreferences) async throws -> Void

    // MARK: Day and plans

    @Published var selectedDate: Date {
        didSet {
            guard dateKey != SchedulerLogic.dateKey(oldValue) else { return }
            clearRecommendation()
            Task { await load() }
        }
    }
    @Published private(set) var tasks: [HabitTraceTask] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var selectedTaskID: String?

    // MARK: Prediction

    @Published private(set) var prediction: AIPredictResponse?
    @Published private(set) var isPredicting = false
    @Published private(set) var predictionFailed = false

    // MARK: Recommendations and moves

    @Published private(set) var recommendation: TimeRecommendation?
    @Published private(set) var isRecommending = false
    @Published private(set) var recommendationError: String?
    @Published private(set) var isSaving = false

    // MARK: Availability

    /// The saved window used for slots and recommendations.
    @Published private(set) var preferences: PlanningPreferences
    /// Editable copies; saved via `saveAvailability()`.
    @Published var draftWorkStart: String
    @Published var draftWorkEnd: String
    @Published private(set) var isSavingAvailability = false
    @Published private(set) var availabilityError: String?

    @Published var toast: HTToastMessage?

    private let taskService: TaskService
    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider
    private let savePreferences: PreferencesSaver
    private let now: () -> Date
    private var loadGeneration = 0
    private var predictionGeneration = 0
    private var predictionKey: String?

    init(
        taskService: TaskService,
        apiClient: APIClient = APIClient(),
        accessTokenProvider: @escaping AccessTokenProvider,
        preferences: PlanningPreferences,
        savePreferences: @escaping PreferencesSaver,
        initialDate: Date = .now,
        initialTaskID: String? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.taskService = taskService
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.savePreferences = savePreferences
        self.preferences = preferences
        self.draftWorkStart = preferences.workStart
        self.draftWorkEnd = preferences.workEnd
        self.selectedDate = initialDate
        self.selectedTaskID = initialTaskID
        self.now = now
    }

    // MARK: - Derived values

    /// `"yyyy-MM-dd"` for the selected day.
    var dateKey: String { SchedulerLogic.dateKey(selectedDate) }

    var isToday: Bool { dateKey == SchedulerLogic.dateKey(now()) }

    var selectedTask: HabitTraceTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    /// Pending plans that intersect another pending plan on this day.
    var overlappingIDs: Set<String> {
        SchedulerLogic.overlappingPendingIDs(tasks.map(SchedulerLogic.PlanSlot.init(task:)))
    }

    /// Up to eight conflict-free start times for the selected plan.
    var slots: [Int] {
        guard let task = selectedTask else { return [] }
        return SchedulerLogic.freeSlots(
            for: SchedulerLogic.PlanSlot(task: task),
            among: tasks.map(SchedulerLogic.PlanSlot.init(task:)),
            workStart: preferences.workStart,
            workEnd: preferences.workEnd,
            notBefore: isToday ? SchedulerLogic.minutesSinceMidnight(now()) : 0,
            limit: SchedulerLogic.maxSlots
        )
    }

    var successPercent: Int? { prediction?.successPercent }

    /// The button is enabled only once the plan is linked and a slot exists.
    var canRequestRecommendations: Bool {
        selectedTask?.aiPlanInputId != nil && !slots.isEmpty && !isRecommending
    }

    /// Top four ranked candidates.
    var topCandidates: [TimeCandidate] {
        Array((recommendation?.rankedCandidates ?? []).prefix(4))
    }

    /// Adopts preferences saved elsewhere (Settings) when the session changes.
    func refreshPreferences(_ latest: PlanningPreferences) {
        guard latest != preferences else { return }
        preferences = latest
        draftWorkStart = latest.workStart
        draftWorkEnd = latest.workEnd
    }

    // MARK: - Loading

    func load() async {
        loadGeneration += 1
        let current = loadGeneration
        isLoading = true
        loadFailed = false

        do {
            let token = try await accessTokenProvider()
            let fetched = try await taskService.fetchTasks(accessToken: token, on: dateKey)
            guard current == loadGeneration else { return }
            tasks = fetched.sorted { ($0.startMinutes ?? Int.max) < ($1.startMinutes ?? Int.max) }
        } catch is CancellationError {
            return
        } catch {
            guard current == loadGeneration else { return }
            if (error as? URLError)?.code == .cancelled { return }
            tasks = []
            loadFailed = true
        }

        if current == loadGeneration {
            isLoading = false
            reconcilePrediction()
        }
    }

    func selectTask(_ id: String?) {
        guard id != selectedTaskID else { return }
        selectedTaskID = id
        clearRecommendation()
        reconcilePrediction()
    }

    // MARK: - Prediction

    /// Starts a prediction load when the selected plan (or its plan input)
    /// changed; mirrors the PWA effect keyed on `task.id`/`ai_plan_input_id`.
    private func reconcilePrediction() {
        let key = selectedTask.map { "\($0.id)|\($0.aiPlanInputId ?? "")" }
        guard key != predictionKey else { return }
        predictionKey = key
        predictionGeneration += 1
        prediction = nil
        predictionFailed = false

        guard let task = selectedTask else {
            isPredicting = false
            return
        }
        isPredicting = true
        let generation = predictionGeneration
        Task { await loadPrediction(for: task, generation: generation) }
    }

    private func loadPrediction(for task: HabitTraceTask, generation: Int) async {
        do {
            let token = try await accessTokenProvider()
            let planID = try await apiClient.ensureAIPlan(accessToken: token, task: task)
            guard generation == predictionGeneration else { return }

            if task.aiPlanInputId == nil, let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].aiPlanInputId = planID
                predictionKey = "\(task.id)|\(planID)"
            }

            let result = try await apiClient.getOrCreateAIPlanPrediction(accessToken: token, planInputID: planID)
            guard generation == predictionGeneration else { return }
            prediction = result
        } catch is CancellationError {
            return
        } catch {
            guard generation == predictionGeneration else { return }
            predictionFailed = true
        }
        isPredicting = false
    }

    // MARK: - Moving a plan

    /// Saves a new start time for the selected plan. When `accepted` is
    /// given, also records the chosen AI candidate (best effort).
    func move(toMinutes minutes: Int, accepted: (recommendationID: String, candidateID: String)? = nil) async {
        guard let task = selectedTask, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let storedTime = SchedulerLogic.storedTime(minutes: minutes)
        do {
            let token = try await accessTokenProvider()
            _ = try await taskService.editTask(
                accessToken: token,
                taskId: task.id,
                title: task.title,
                notes: task.notes,
                taskCategory: task.taskCategory ?? TaskCategory.other.rawValue,
                plannedStartTime: storedTime,
                plannedDate: task.plannedDate,
                plannedDurationMin: task.plannedDurationMin ?? preferences.defaultDuration,
                importance: task.importance ?? 3,
                energyLevel: task.energyLevel ?? 3,
                focusLevel: task.focusLevel ?? 3
            )

            var selectionRecorded = true
            if let accepted {
                do {
                    _ = try await apiClient.selectTimeCandidate(
                        accessToken: token,
                        recommendationID: accepted.recommendationID,
                        candidateID: accepted.candidateID
                    )
                } catch {
                    selectionRecorded = false
                }
            }

            toast = selectionRecorded
                ? .success("Plan rescheduled · \(TaskTimeFormatting.displayTime(storedTime))")
                : .success("Time saved. The AI ranking choice could not be recorded, but your plan was moved.")
            clearRecommendation()
            await load()
        } catch {
            toast = .error("Couldn't change the time. Your original plan is unchanged. Please try again.")
        }
    }

    /// Moves the plan to a ranked candidate and records the choice.
    func accept(_ candidate: TimeCandidate) async {
        guard let recommendation, let minutes = SchedulerLogic.localMinutes(isoTimestamp: candidate.candidateStart) else { return }
        await move(toMinutes: minutes, accepted: (recommendation.id, candidate.id))
    }

    // MARK: - Personalized recommendations

    func rankTimes() async {
        guard let task = selectedTask, let planID = task.aiPlanInputId, !isRecommending else { return }
        let startMinutes = PlanningPreferences.minutes(from: preferences.workStart)
        let endMinutes = PlanningPreferences.minutes(from: preferences.workEnd)
        let earliest = isToday
            ? max(startMinutes, SchedulerLogic.roundUp(SchedulerLogic.minutesSinceMidnight(now()), to: SchedulerLogic.stepMinutes))
            : startMinutes

        if earliest + (task.plannedDurationMin ?? 0) > endMinutes {
            recommendation = nil
            recommendationError = "No remaining time inside your daily availability fits this plan."
            return
        }
        guard let earliestStart = SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: earliest),
              let latestEnd = SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: endMinutes)
        else {
            recommendationError = "Personalized recommendations are unavailable for this window. The conflict-free times above are still available."
            return
        }

        isRecommending = true
        recommendationError = nil
        do {
            let token = try await accessTokenProvider()
            recommendation = try await apiClient.createTimeRecommendation(
                accessToken: token,
                planInputID: planID,
                request: TimeRecommendationRequest(
                    earliestStart: earliestStart,
                    latestEnd: latestEnd,
                    slotIntervalMinutes: SchedulerLogic.stepMinutes,
                    minimumBufferMinutes: SchedulerLogic.bufferMinutes
                )
            )
        } catch {
            recommendation = nil
            recommendationError = "Personalized recommendations are unavailable for this window. The conflict-free times above are still available."
        }
        isRecommending = false
    }

    private func clearRecommendation() {
        recommendation = nil
        recommendationError = nil
    }

    // MARK: - Daily availability

    func saveAvailability() async {
        guard !isSavingAvailability else { return }
        if draftWorkEnd <= draftWorkStart {
            availabilityError = "Daily availability must end after it starts."
            return
        }

        isSavingAvailability = true
        availabilityError = nil
        var next = preferences
        next.workStart = draftWorkStart
        next.workEnd = draftWorkEnd

        do {
            try await savePreferences(next)
            preferences = next
            toast = .success("Daily availability saved · \(PlanningPreferences.displayTime(next.workStart)) – \(PlanningPreferences.displayTime(next.workEnd))")
        } catch {
            availabilityError = "Couldn't save daily availability. Your previous times are still active until this succeeds."
        }
        isSavingAvailability = false
    }
}
