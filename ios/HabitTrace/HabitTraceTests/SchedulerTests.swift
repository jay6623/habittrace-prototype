import Foundation
import Testing
@testable import HabitTrace

// MARK: - Pure scheduling logic

/// `findFreeSlots` port, timestamp building, form validation, and the
/// `ensureAIPlan` decision. Runs off the main actor.
struct SchedulerLogicTests {
    private func slot(
        _ id: String,
        start: Int?,
        duration: Int = 30,
        date: String? = "2026-11-10",
        pending: Bool = true
    ) -> SchedulerLogic.PlanSlot {
        SchedulerLogic.PlanSlot(id: id, dateKey: date, startMinutes: start, durationMinutes: duration, isPending: pending)
    }

    @Test func freeSlotsKeepABufferAroundOtherPendingPlans() {
        let selected = slot("a", start: 8 * 60, duration: 30)
        let other = slot("b", start: 10 * 60, duration: 60)

        let slots = SchedulerLogic.freeSlots(for: selected, among: [selected, other], workStart: "09:00", workEnd: "12:00")

        // 9:00 and 9:15 end at least 15 minutes before 10:00; 11:15 onward
        // starts at least 15 minutes after 11:00; 11:45 would overrun 12:00.
        #expect(slots == [540, 555, 675, 690])
    }

    @Test func freeSlotsIgnoreFinishedPlansAndOtherDays() {
        let selected = slot("a", start: nil, duration: 30)
        let finished = slot("b", start: 9 * 60, duration: 120, pending: false)
        let tomorrow = slot("c", start: 9 * 60, duration: 120, date: "2026-11-11")
        let unparsable = slot("d", start: nil, duration: 60)

        let slots = SchedulerLogic.freeSlots(
            for: selected,
            among: [selected, finished, tomorrow, unparsable],
            workStart: "09:00",
            workEnd: "10:00"
        )

        #expect(slots == [540, 555, 570])
    }

    @Test func freeSlotsStartAtTheNextQuarterHourAfterNow() {
        let selected = slot("a", start: 8 * 60, duration: 30)

        let slots = SchedulerLogic.freeSlots(for: selected, among: [selected], workStart: "09:00", workEnd: "11:00", notBefore: 9 * 60 + 50)

        #expect(slots == [600, 615, 630])
    }

    @Test func freeSlotsHonorTheDisplayLimit() {
        let selected = slot("a", start: 8 * 60, duration: 15)

        let all = SchedulerLogic.freeSlots(for: selected, among: [selected], workStart: "09:00", workEnd: "22:00")
        let limited = SchedulerLogic.freeSlots(for: selected, among: [selected], workStart: "09:00", workEnd: "22:00", limit: SchedulerLogic.maxSlots)

        #expect(all.count > 8)
        #expect(limited == Array(all.prefix(8)))
    }

    @Test func overlappingPendingPlansAreFlaggedPairwise() {
        let plans = [
            slot("a", start: 9 * 60, duration: 60),
            slot("b", start: 9 * 60 + 30, duration: 30),
            slot("c", start: 10 * 60, duration: 30),
            slot("d", start: 9 * 60, duration: 60, pending: false),
        ]

        #expect(SchedulerLogic.overlappingPendingIDs(plans) == ["a", "b"])
    }

    @Test func isoTimestampsRoundTripThroughLocalMinutes() throws {
        let timestamp = try #require(SchedulerLogic.isoTimestamp(dateKey: "2026-11-10", minutes: 9 * 60 + 30))
        let parsed = try #require(TaskTimeFormatting.date(fromISO8601: timestamp))

        #expect(SchedulerLogic.localMinutes(isoTimestamp: timestamp) == 570)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: parsed) == DateComponents(year: 2026, month: 11, day: 10))
        #expect(SchedulerLogic.isoTimestamp(dateKey: "2026-11-10", time: "09:30") == timestamp)
        #expect(SchedulerLogic.isoTimestamp(dateKey: "2026-11-10", time: "9:30") == nil)
        #expect(SchedulerLogic.isoTimestamp(dateKey: "nope", minutes: 0) == nil)
    }

    @Test func storedTimeMatchesThePWAForm() {
        #expect(SchedulerLogic.storedTime(minutes: 0) == "12:00 AM")
        #expect(SchedulerLogic.storedTime(minutes: 9 * 60 + 30) == "9:30 AM")
        #expect(SchedulerLogic.storedTime(minutes: 12 * 60) == "12:00 PM")
        #expect(SchedulerLogic.storedTime(minutes: 13 * 60 + 5) == "1:05 PM")
        #expect(SchedulerLogic.roundUp(590, to: 15) == 600)
        #expect(SchedulerLogic.roundUp(600, to: 15) == 600)
    }

    @Test func aiPlanResolutionReusesLinkedPlans() throws {
        #expect(AIPlanResolution.resolve(planInputID: "plan-1") == .ready(planID: "plan-1"))
        #expect(AIPlanResolution.resolve(planInputID: nil) == .needsSync)
        #expect(AIPlanResolution.resolve(planInputID: "") == .needsSync)
        #expect(try AIPlanResolution.planID(fromSyncedPlanInputID: "plan-2") == "plan-2")
        #expect(throws: SchedulerError.aiPlanPending) {
            try AIPlanResolution.planID(fromSyncedPlanInputID: nil)
        }
    }

    @Test func generateFormValidationUsesThePWAMessages() {
        var form = GenerateDayForm(dateKey: "2026-11-10", dayStart: "09:00", dayEnd: "22:00")
        #expect(form.validationError == "Add at least one task with a title.")

        form.tasks[0].title = "  Write report "
        #expect(form.validationError == "Choose a category for Write report.")

        form.tasks[0].category = "Work"
        form.tasks[0].isFixedTime = true
        #expect(form.validationError == "Choose a fixed time for Write report.")

        form.tasks[0].fixedStartMinutes = 10 * 60
        form.dayEnd = "09:00"
        #expect(form.validationError == "Your day must end after it starts.")

        form.dayEnd = "22:00"
        #expect(form.validationError == nil)
        #expect(form.makeRequest(timezoneName: "UTC") != nil)
    }

    @Test func generateFormBuildsTheRequestBody() throws {
        var form = GenerateDayForm(dateKey: "2026-11-10", dayStart: "08:00", dayEnd: "20:00", bufferMinutes: 10)
        form.tasks[0].title = "Write report"
        form.tasks[0].category = "Work"
        form.tasks[0].durationMinutes = 60
        form.tasks[0].importance = 4
        var fixed = GenerateDayTaskDraft()
        fixed.title = "Standup"
        fixed.category = "Work"
        fixed.isFixedTime = true
        fixed.fixedStartMinutes = 9 * 60
        fixed.deadlineMinutes = 10 * 60
        var blank = GenerateDayTaskDraft()
        blank.title = "   "
        form.tasks += [fixed, blank]

        let request = try #require(form.makeRequest(timezoneName: "Asia/Kuala_Lumpur"))
        #expect(request.selectedDate == "2026-11-10")
        #expect(request.dayStart == "08:00")
        #expect(request.dayEnd == "20:00")
        #expect(request.minimumBufferMinutes == 10)
        #expect(request.slotIntervalMinutes == 15)
        #expect(request.maxPlannedMinutes == 480)
        #expect(request.maxFocusBlockMinutes == 120)
        #expect(request.tasks.count == 2)
        #expect(request.tasks[0].deadlineAt == nil)
        #expect(request.tasks[0].fixedStart == nil)
        #expect(request.tasks[0].isFixedTime == false)
        #expect(request.tasks[1].fixedStart == SchedulerLogic.isoTimestamp(dateKey: "2026-11-10", minutes: 9 * 60))
        #expect(request.tasks[1].deadlineAt == SchedulerLogic.isoTimestamp(dateKey: "2026-11-10", minutes: 10 * 60))

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try #require(try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        let tasks = try #require(json["tasks"] as? [[String: Any]])
        #expect(tasks[0]["deadline_at"] is NSNull)
        #expect(tasks[0]["fixed_start"] is NSNull)
        #expect(tasks[0]["estimated_duration_minutes"] as? Int == 60)
        #expect(tasks[0]["required_energy"] as? Int == 3)
        #expect((tasks[0]["client_id"] as? String)?.isEmpty == false)
        #expect(json["timezone_name"] as? String == "Asia/Kuala_Lumpur")
    }

    @Test func predictionDecodesLenientlyFromTheBackendShape() throws {
        let data = StubURLProtocol.encode([
            "model_version": "v2", "success_probability": 0.724, "base_success_probability": NSNull(),
            "personalization": [:], "failure_reason_probabilities": ["other": 1],
            "predicted_failure_reason": NSNull(), "predicted_at": "2026-11-09T00:00:00Z",
            "explanation": ["source": "model", "factors": [["feature": "x"]]],
            "recommended_actions": [["code": "shorter", "title": "Shorter block", "detail": "Try 25 minutes."]],
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let prediction = try decoder.decode(AIPredictResponse.self, from: data)

        #expect(prediction.successPercent == 72)
        #expect(prediction.personalization?.applied == false)
        #expect(prediction.recommendedActions.map(\.title) == ["Shorter block"])
    }
}

// MARK: - Stubbed network flows

extension StubbedNetworkSuites {

/// Find-a-time and generate-day flows against `StubURLProtocol`.
@MainActor
@Suite
struct SchedulerFlowTests {
    private let dateKey = "2030-01-07"
    private var day: Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!
    }

    private func taskJSON(id: String, start: String = "9:00 AM", planID: String?) -> [String: Any] {
        [
            "id": id, "title": "Write report", "notes": NSNull(), "task_category": "Work",
            "planned_date": dateKey, "planned_start_time": start, "planned_duration_min": 30,
            "importance": 3, "energy_level": 3, "focus_level": 3, "task_status": "pending",
            "created_at": "2030-01-01T00:00:00Z", "ai_plan_input_id": planID ?? NSNull(), "ai_sync_status": planID == nil ? "pending" : "synced",
        ]
    }

    private var predictionJSON: [String: Any] {
        [
            "model_version": "v2", "success_probability": 0.72, "base_success_probability": 0.6,
            "personalization": [
                "applied": true, "sample_count": 6, "confidence": 0.8, "history_success_rate": 0.7,
                "factors": [["type": "category", "direction": "positive", "sample_count": 6, "message": "Work plans finish most often."]],
            ],
            "failure_reason_probabilities": ["other": 1], "predicted_failure_reason": NSNull(),
            "predicted_at": "2030-01-01T00:00:00Z", "explanation": ["source": "model"],
            "recommended_actions": [["code": "shorter", "title": "Shorter block", "detail": "Try 25 minutes."]],
        ]
    }

    private func recommendationJSON(status: String = "generated") -> [String: Any] {
        [
            "id": "rec-1", "plan_input_id": "plan-1", "model_version_id": "m", "status": status,
            "earliest_start": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 9 * 60)!,
            "latest_end": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 22 * 60)!,
            "slot_interval_minutes": 15, "minimum_buffer_minutes": 15, "selected_candidate_id": NSNull(),
            "created_at": "2030-01-01T00:00:00Z",
            "candidates": [[
                "id": "c1", "recommendation_id": "rec-1",
                "candidate_start": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 14 * 60)!,
                "candidate_end": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 14 * 60 + 30)!,
                "predicted_success_probability": 0.81, "conflict_penalty": 0, "overload_penalty": 0,
                "preference_penalty": 0, "final_score": 0.8, "rank": 1,
                "reason_snapshot": ["strategy": "ranked", "personalization": ["applied": true, "sample_count": 4]],
            ]],
        ]
    }

    private func scheduleJSON(status: String, startMinutes: Int) -> [String: Any] {
        [
            "id": "sched-1", "user_id": "u", "selected_date": dateKey, "timezone_name": "Asia/Kuala_Lumpur",
            "day_start": "09:00:00", "day_end": "22:00:00", "minimum_buffer_minutes": 10, "slot_interval_minutes": 15,
            "max_planned_minutes": 480, "max_focus_block_minutes": 120, "status": status,
            "scheduled_tasks": [[
                "task_id": "task-1", "title": "Write report", "estimated_duration_minutes": 60, "deadline_at": NSNull(),
                "importance": 4, "category": "Work", "difficulty": 3, "required_energy": 3, "required_focus": 3,
                "is_fixed_time": false,
                "scheduled_start": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: startMinutes)!,
                "scheduled_end": SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: startMinutes + 60)!,
                "predicted_success_probability": 0.66, "final_score": 0.6, "explanation": "Morning focus.",
                "created_task_id": NSNull(), "plan_input_id": NSNull(),
            ]],
            "unscheduled_tasks": [], "warnings": ["One warning"],
            "created_at": "2030-01-01T00:00:00Z", "confirmed_at": status == "confirmed" ? "2030-01-07T01:00:00Z" : NSNull(),
        ]
    }

    private func makeFindTime(client: APIClient, taskID: String?) -> FindTimeViewModel {
        FindTimeViewModel(
            taskService: TaskService(apiClient: client),
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            savePreferences: { _ in },
            initialDate: day,
            initialTaskID: taskID
        )
    }

    /// Waits for the detached prediction load to settle.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private var requestLog: [String] {
        StubURLProtocol.recordedRequests.map { "\($0.method) \($0.path)" }
    }

    @Test func findTimeLoadsPlansSyncsThePlanAndPredicts() async throws {
        let tasks = StubURLProtocol.encode([taskJSON(id: "t1", planID: nil)])
        let synced = StubURLProtocol.encode(taskJSON(id: "t1", planID: "plan-1"))
        let noPrediction = StubURLProtocol.encode(["prediction": NSNull()])
        let prediction = StubURLProtocol.encode(predictionJSON)
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/tasks"): return .json(200, tasks)
            case ("POST", "/tasks/t1/ai-plan"): return .json(200, synced)
            case ("GET", "/api/v2/ai/plans/plan-1/prediction"): return .json(200, noPrediction)
            case ("POST", "/api/v2/ai/plans/plan-1/predict"): return .json(200, prediction)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let viewModel = makeFindTime(client: client, taskID: "t1")

        await viewModel.load()
        await waitUntil { !viewModel.isPredicting }

        #expect(viewModel.loadFailed == false)
        #expect(viewModel.tasks.map(\.id) == ["t1"])
        #expect(viewModel.selectedTask?.aiPlanInputId == "plan-1")
        #expect(viewModel.successPercent == 72)
        #expect(viewModel.predictionFailed == false)
        #expect(viewModel.prediction?.personalization?.sampleCount == 6)
        #expect(viewModel.prediction?.recommendedActions.first?.detail == "Try 25 minutes.")
        // The selected plan is the only one that day, so the first slot is
        // the start of the availability window; the plan itself never
        // blocks its own candidates.
        #expect(viewModel.slots.first == 9 * 60)
        #expect(viewModel.canRequestRecommendations)
        #expect(requestLog == [
            "GET /tasks",
            "POST /tasks/t1/ai-plan",
            "GET /api/v2/ai/plans/plan-1/prediction",
            "POST /api/v2/ai/plans/plan-1/predict",
        ])
        let tasksRequest = try #require(StubURLProtocol.recordedRequests.first)
        #expect(tasksRequest.queryParameters["date"] == dateKey)
        let syncRequest = try #require(StubURLProtocol.recordedRequests.first { $0.path == "/tasks/t1/ai-plan" })
        #expect((syncRequest.body?["timezone_name"] as? String)?.isEmpty == false)
        StubURLProtocol.reset()
    }

    @Test func findTimeReportsLoadFailures() async {
        StubURLProtocol.install { _ in .detail(500, "boom") }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let viewModel = makeFindTime(client: client, taskID: nil)

        await viewModel.load()

        #expect(viewModel.loadFailed)
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.isLoading == false)
        StubURLProtocol.reset()
    }

    @Test func rankTimesSendsTheWindowAndRecordsTheAcceptedCandidate() async throws {
        let tasks = StubURLProtocol.encode([taskJSON(id: "t1", planID: "plan-1")])
        let moved = StubURLProtocol.encode(taskJSON(id: "t1", start: "2:00 PM", planID: "plan-1"))
        let existing = StubURLProtocol.encode(["prediction": predictionJSON])
        let recommendation = StubURLProtocol.encode(recommendationJSON())
        let accepted = StubURLProtocol.encode(recommendationJSON(status: "accepted"))
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/tasks"): return .json(200, tasks)
            case ("GET", "/api/v2/ai/plans/plan-1/prediction"): return .json(200, existing)
            case ("POST", "/api/v2/ai/plans/plan-1/time-recommendations"): return .json(201, recommendation)
            case ("PATCH", "/tasks/t1"): return .json(200, moved)
            case ("POST", "/api/v2/ai/time-recommendations/rec-1/select"): return .json(200, accepted)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let viewModel = makeFindTime(client: client, taskID: "t1")
        await viewModel.load()
        await waitUntil { !viewModel.isPredicting }
        #expect(requestLog.contains("POST /api/v2/ai/plans/plan-1/predict") == false)

        await viewModel.rankTimes()

        #expect(viewModel.recommendationError == nil)
        #expect(viewModel.topCandidates.map(\.id) == ["c1"])
        let rankRequest = try #require(StubURLProtocol.recordedRequests.first { $0.path.hasSuffix("/time-recommendations") })
        #expect(rankRequest.body?["earliest_start"] as? String == SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 9 * 60))
        #expect(rankRequest.body?["latest_end"] as? String == SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 22 * 60))
        #expect(rankRequest.body?["slot_interval_minutes"] as? Int == 15)
        #expect(rankRequest.body?["minimum_buffer_minutes"] as? Int == 15)

        let candidate = try #require(viewModel.topCandidates.first)
        await viewModel.accept(candidate)

        let patch = try #require(StubURLProtocol.recordedRequests.first { $0.method == "PATCH" })
        #expect(patch.body?["planned_start_time"] as? String == "2:00 PM")
        #expect(patch.body?["title"] as? String == "Write report")
        let select = try #require(StubURLProtocol.recordedRequests.first { $0.path.hasSuffix("/select") })
        #expect(select.body?["candidate_id"] as? String == "c1")
        #expect(select.body?["status"] as? String == "accepted")
        let patchIndex = try #require(requestLog.firstIndex(of: "PATCH /tasks/t1"))
        let selectIndex = try #require(requestLog.firstIndex(of: "POST /api/v2/ai/time-recommendations/rec-1/select"))
        #expect(patchIndex < selectIndex)
        #expect(viewModel.toast?.text.hasPrefix("Plan rescheduled") == true)
        #expect(viewModel.recommendation == nil)
        #expect(requestLog.filter { $0 == "GET /tasks" }.count == 2)
        StubURLProtocol.reset()
    }

    @Test func rankTimesReportsWhenNoWindowRemainsToday() async {
        let tasks = StubURLProtocol.encode([taskJSON(id: "t1", planID: "plan-1")])
        let existing = StubURLProtocol.encode(["prediction": predictionJSON])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/tasks"): return .json(200, tasks)
            case ("GET", "/api/v2/ai/plans/plan-1/prediction"): return .json(200, existing)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let lateEvening = Calendar.current.date(bySettingHour: 21, minute: 50, second: 0, of: day)!
        let viewModel = FindTimeViewModel(
            taskService: TaskService(apiClient: client),
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            savePreferences: { _ in },
            initialDate: day,
            initialTaskID: "t1",
            now: { lateEvening }
        )
        await viewModel.load()
        await waitUntil { !viewModel.isPredicting }

        #expect(viewModel.isToday)
        #expect(viewModel.slots.isEmpty)
        await viewModel.rankTimes()

        #expect(viewModel.recommendationError == "No remaining time inside your daily availability fits this plan.")
        #expect(requestLog.contains { $0.hasSuffix("/time-recommendations") } == false)
        StubURLProtocol.reset()
    }

    @Test func saveAvailabilityValidatesAndPersists() async {
        StubURLProtocol.install { _ in .json(200, StubURLProtocol.encode([])) }
        let client = APIClient(session: StubURLProtocol.makeSession())
        nonisolated(unsafe) var saved: PlanningPreferences?
        let viewModel = FindTimeViewModel(
            taskService: TaskService(apiClient: client),
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            savePreferences: { saved = $0 },
            initialDate: day
        )

        viewModel.draftWorkStart = "10:00"
        viewModel.draftWorkEnd = "09:00"
        await viewModel.saveAvailability()
        #expect(viewModel.availabilityError == "Daily availability must end after it starts.")
        #expect(saved == nil)

        viewModel.draftWorkEnd = "18:00"
        await viewModel.saveAvailability()
        #expect(viewModel.availabilityError == nil)
        #expect(saved == PlanningPreferences(defaultDuration: 30, workStart: "10:00", workEnd: "18:00"))
        #expect(viewModel.preferences.workStart == "10:00")
        #expect(viewModel.toast?.text.hasPrefix("Daily availability saved") == true)
        StubURLProtocol.reset()
    }

    @Test func generateAdjustAndConfirmADraft() async throws {
        let draft = StubURLProtocol.encode(scheduleJSON(status: "draft", startMinutes: 9 * 60))
        let adjusted = StubURLProtocol.encode(scheduleJSON(status: "draft", startMinutes: 10 * 60))
        let confirmed = StubURLProtocol.encode(scheduleJSON(status: "confirmed", startMinutes: 10 * 60))
        let empty = StubURLProtocol.encode([])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/api/v2/ai/daily-schedules/generate"): return .json(201, draft)
            case ("PATCH", "/api/v2/ai/daily-schedules/sched-1"): return .json(200, adjusted)
            case ("POST", "/api/v2/ai/daily-schedules/sched-1/confirm"): return .json(200, confirmed)
            case ("GET", "/tasks"): return .json(200, empty)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let taskService = TaskService(apiClient: client)
        let viewModel = GenerateDayViewModel(
            taskService: taskService,
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            initialDate: day,
            timezoneName: "Asia/Kuala_Lumpur"
        )
        viewModel.form.tasks[0].title = "Write report"
        viewModel.form.tasks[0].category = "Work"
        viewModel.form.tasks[0].durationMinutes = 60
        viewModel.form.tasks[0].importance = 4
        viewModel.form.bufferMinutes = 10

        await viewModel.generate()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.result?.schedule.id == "sched-1")
        #expect(viewModel.isDraft)
        #expect(viewModel.result?.bufferMinutes == 10)
        #expect(viewModel.result?.meta.importance(for: "task-1") == 4)
        #expect(viewModel.result?.meta.isFixedTime("task-1") == false)
        #expect(viewModel.result?.schedule.warnings == ["One warning"])
        #expect(viewModel.toast?.text == "Draft schedule generated. Review and adjust it before confirming.")
        let generate = try #require(StubURLProtocol.recordedRequests.first)
        #expect(generate.body?["selected_date"] as? String == dateKey)
        #expect(generate.body?["timezone_name"] as? String == "Asia/Kuala_Lumpur")
        #expect(generate.body?["day_start"] as? String == "09:00")
        #expect(generate.body?["day_end"] as? String == "22:00")
        #expect(generate.body?["minimum_buffer_minutes"] as? Int == 10)
        #expect(generate.body?["slot_interval_minutes"] as? Int == 15)
        #expect(generate.body?["max_planned_minutes"] as? Int == 480)
        #expect(generate.body?["max_focus_block_minutes"] as? Int == 120)
        let sentTasks = try #require(generate.body?["tasks"] as? [[String: Any]])
        #expect(sentTasks.count == 1)
        #expect(sentTasks[0]["title"] as? String == "Write report")
        #expect(sentTasks[0]["category"] as? String == "Work")
        #expect(sentTasks[0]["estimated_duration_minutes"] as? Int == 60)
        #expect(sentTasks[0]["importance"] as? Int == 4)
        #expect(sentTasks[0]["is_fixed_time"] as? Bool == false)
        #expect(sentTasks[0]["deadline_at"] is NSNull)
        #expect(sentTasks[0]["fixed_start"] is NSNull)

        await viewModel.moveTask(taskID: "task-1", toMinutes: 10 * 60)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.toast?.text == "Draft time updated")
        #expect(viewModel.result?.schedule.scheduledTasks.first?.scheduledStart == SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 10 * 60))
        let patch = try #require(StubURLProtocol.recordedRequests.first { $0.method == "PATCH" })
        let adjustments = try #require(patch.body?["adjustments"] as? [[String: Any]])
        #expect(adjustments.count == 1)
        #expect(adjustments[0]["task_id"] as? String == "task-1")
        #expect(adjustments[0]["scheduled_start"] as? String == SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: 10 * 60))

        await viewModel.confirm()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isDraft == false)
        #expect(viewModel.result?.schedule.status == "confirmed")
        #expect(viewModel.result?.bufferMinutes == 10)
        #expect(viewModel.toast?.text == "Daily plan confirmed. The scheduled tasks are now in HabitTrace.")
        #expect(requestLog == [
            "POST /api/v2/ai/daily-schedules/generate",
            "PATCH /api/v2/ai/daily-schedules/sched-1",
            "POST /api/v2/ai/daily-schedules/sched-1/confirm",
            "GET /tasks",
        ])
        StubURLProtocol.reset()
    }

    @Test func generateValidationAndServerErrorsUseThePWAMessages() async {
        StubURLProtocol.install { _ in .detail(422, "day_end must be after day_start") }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let viewModel = GenerateDayViewModel(
            taskService: TaskService(apiClient: client),
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            initialDate: day
        )

        await viewModel.generate()
        #expect(viewModel.errorMessage == "Add at least one task with a title.")
        #expect(StubURLProtocol.recordedRequests.isEmpty)

        viewModel.form.tasks[0].title = "Write report"
        viewModel.form.tasks[0].category = "Work"
        await viewModel.generate()
        #expect(viewModel.errorMessage == "day_end must be after day_start")
        #expect(viewModel.result == nil)

        StubURLProtocol.install { _ in throw URLError(.notConnectedToInternet) }
        await viewModel.generate()
        #expect(viewModel.errorMessage == "We couldn't generate a schedule. Check the backend connection and try again.")
        StubURLProtocol.reset()
    }

    @Test func deepLinkedDraftLoadsOnce() async {
        let draft = StubURLProtocol.encode(scheduleJSON(status: "draft", startMinutes: 9 * 60))
        StubURLProtocol.install { request in
            request.path == "/api/v2/ai/daily-schedules/sched-1" ? .json(200, draft) : .detail(500, "unexpected")
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        let viewModel = GenerateDayViewModel(
            taskService: TaskService(apiClient: client),
            apiClient: client,
            accessTokenProvider: { "token" },
            preferences: .default,
            initialDate: day,
            draftID: "sched-1"
        )

        await viewModel.loadDraftIfNeeded()
        await viewModel.loadDraftIfNeeded()

        #expect(viewModel.result?.schedule.id == "sched-1")
        #expect(viewModel.isLoadingDraft == false)
        #expect(requestLog == ["GET /api/v2/ai/daily-schedules/sched-1"])
        StubURLProtocol.reset()
    }
}

}
