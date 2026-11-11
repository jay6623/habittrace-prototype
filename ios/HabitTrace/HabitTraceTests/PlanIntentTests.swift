import Foundation
import Testing
@testable import HabitTrace

/// Spoken dialogs and duplicate detection behind the Siri intents.
@MainActor
struct PlanIntentLogicTests {
    private func task(_ id: String, _ title: String, time: String?, status: String? = "pending", date: String = "2026-11-10") -> HabitTraceTask {
        HabitTraceTask(
            id: id, title: title, notes: nil, taskCategory: "Work",
            plannedDate: date, plannedStartTime: time, plannedDurationMin: 30,
            importance: 3, energyLevel: 3, focusLevel: 3, taskStatus: status, createdAt: nil
        )
    }

    /// Spoken times follow the device locale, so expectations are built
    /// with the same formatter the dialog uses.
    private func spoken(_ time: String) -> String {
        TaskTimeFormatting.displayTime(time)
    }

    @Test func emptyDayIsSpokenPlainly() {
        #expect(PlanIntentLogic.todaysPlansDialog(for: []) == "You have no plans today.")
    }

    @Test func plansAreSortedAndJoinedForSpeech() {
        let dialog = PlanIntentLogic.todaysPlansDialog(for: [
            task("b", "Gym", time: "6:00 PM"),
            task("a", "Write report", time: "9:00 AM", status: "success"),
            task("c", "Read", time: "21:00"),
        ])
        #expect(dialog == "You have 3 plans today: Write report at \(spoken("9:00 AM")), Gym at \(spoken("6:00 PM")), and Read at \(spoken("21:00")). 2 still to go.")
    }

    @Test func longDaysAreTruncated() {
        let tasks = (0..<7).map { task("\($0)", "Plan \($0)", time: "\(8 + $0):00") }
        let dialog = PlanIntentLogic.todaysPlansDialog(for: tasks)
        #expect(dialog.hasPrefix("You have 7 plans today: Plan 0 at \(spoken("8:00")), Plan 1 at"))
        #expect(dialog.hasSuffix("Plan 4 at \(spoken("12:00")), and 2 more."))
        #expect(!dialog.contains(", and Plan 4"), "the list is not closed with 'and' when more follow")
    }

    @Test func duplicateMatchesPendingTitleAndTimeOnly() {
        let existing = [
            task("1", "Write report", time: "2:00 PM"),
            task("2", "Gym", time: "6:00 PM", status: "success"),
        ]
        #expect(PlanIntentLogic.duplicate(title: "  write REPORT ", startMinutes: 14 * 60, in: existing)?.id == "1")
        #expect(PlanIntentLogic.duplicate(title: "Write report", startMinutes: 15 * 60, in: existing) == nil)
        #expect(PlanIntentLogic.duplicate(title: "Gym", startMinutes: 18 * 60, in: existing) == nil, "finished plans never count as duplicates")
    }

    @Test func confirmationDialogsNameTheDayAndTime() {
        let today = task("1", "Write report", time: "2:00 PM")
        #expect(PlanIntentLogic.addedDialog(for: today, today: "2026-11-10") == "Added “Write report” to your plans today at \(spoken("2:00 PM")).")
        let later = task("2", "Gym", time: "18:00", date: "2026-11-12")
        #expect(PlanIntentLogic.duplicateDialog(for: later, today: "2026-11-10") == "“Gym” is already planned on Nov 12 at \(spoken("18:00")), so I didn't add it again.")
    }
}

extension StubbedNetworkSuites {

/// The intent service against a stubbed backend.
@MainActor
@Suite
struct PlanIntentServiceTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 13, minute: 7))!

    private func makeService(token: String? = "token") -> PlanIntentService {
        PlanIntentService(
            taskService: TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession())),
            tokenProvider: {
                guard let token else { throw PlanIntentError.signedOut }
                return token
            },
            now: { now }
        )
    }

    private func taskJSON(id: String, title: String, time: String, status: String = "pending") -> [String: Any] {
        [
            "id": id, "user_id": "u", "title": title, "task_category": "Work",
            "planned_date": "2026-11-10", "planned_start_time": time, "planned_duration_min": 30,
            "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1,
            "task_status": status, "created_at": "c",
        ]
    }

    @Test func todaysPlansQueryTodayAndSort() async throws {
        let body = StubURLProtocol.encode([
            taskJSON(id: "b", title: "Gym", time: "6:00 PM"),
            taskJSON(id: "a", title: "Report", time: "9:00 AM"),
        ])
        StubURLProtocol.install { _ in .json(200, body) }

        let plans = try await makeService().todaysPlans()

        #expect(plans.map(\.id) == ["a", "b"])
        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.path == "/tasks")
        #expect(request.queryParameters["date"] == "2026-11-10")
        StubURLProtocol.reset()
    }

    @Test func addPlanCreatesLikeQuickAdd() async throws {
        let existing = StubURLProtocol.encode([taskJSON(id: "x", title: "Other", time: "9:00 AM")])
        let created = StubURLProtocol.encode(taskJSON(id: "new", title: "Write report", time: "2:00 PM"))
        StubURLProtocol.install { request in
            request.method == "POST" ? .json(201, created) : .json(200, existing)
        }

        let service = makeService()
        let result = try await service.addPlan(title: " Write report ", start: nil, durationMinutes: nil, category: .work)

        guard case .created(let task) = result else { Issue.record("expected creation"); return }
        #expect(task.id == "new")
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["title"] as? String == "Write report")
        #expect(body["planned_date"] as? String == "2026-11-10")
        #expect(body["planned_start_time"] as? String == "1:15 PM", "defaults to the next quarter hour")
        #expect(body["planned_duration_min"] as? Int == 30)
        #expect(body["task_category"] as? String == "Work")
        #expect(body["total_tasks_today"] as? Int == 2)
        #expect(body["importance"] as? Int == 3)
        StubURLProtocol.reset()
    }

    @Test func addPlanNeverDuplicatesAnExistingPlan() async throws {
        let existing = StubURLProtocol.encode([taskJSON(id: "dup", title: "Write report", time: "2:00 PM")])
        StubURLProtocol.install { _ in .json(200, existing) }
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14))!

        let result = try await makeService().addPlan(title: "write report", start: start, durationMinutes: 45, category: .work)

        guard case .duplicate(let task) = result else { Issue.record("expected duplicate"); return }
        #expect(task.id == "dup")
        #expect(StubURLProtocol.recordedRequests.count == 1)
        #expect(StubURLProtocol.recordedRequests.allSatisfy { $0.method == "GET" }, "no POST is sent for a duplicate")
        StubURLProtocol.reset()
    }

    @Test func signedOutAndInvalidInputFailBeforeTheNetwork() async {
        StubURLProtocol.install { _ in .detail(500, "should not be called") }

        await #expect(throws: PlanIntentError.signedOut) {
            try await makeService(token: nil).todaysPlans()
        }
        await #expect(throws: PlanIntentError.emptyTitle) {
            try await makeService().addPlan(title: "   ", start: nil, durationMinutes: nil, category: .other)
        }
        await #expect(throws: PlanIntentError.titleTooLong) {
            try await makeService().addPlan(title: String(repeating: "x", count: 201), start: nil, durationMinutes: nil, category: .other)
        }
        await #expect(throws: PlanIntentError.invalidDuration) {
            try await makeService().addPlan(title: "Nap", start: nil, durationMinutes: 2, category: .other)
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        StubURLProtocol.reset()
    }

    /// The spoken sentence, resolved, must reach the backend with the stated
    /// day and time rather than the current time.
    @Test func resolvedSentenceIsSavedWithItsOwnDayAndTime() async throws {
        let created = StubURLProtocol.encode(taskJSON(id: "new", title: "Workout", time: "8:00 AM"))
        StubURLProtocol.install { request in
            request.method == "POST" ? .json(201, created) : .json(200, StubURLProtocol.encode([[String: Any]]()))
        }
        let request = PlanRequestResolver.resolve(
            utterance: "Create a workout task tomorrow at 8 AM for 45 minutes.",
            explicitStart: nil, explicitDuration: nil, explicitCategory: nil, now: now
        )
        let start = try #require(request.start())

        let result = try await makeService().addPlan(
            title: request.title, start: start, durationMinutes: request.durationMinutes, category: request.category
        )

        guard case .created = result else { Issue.record("expected creation"); return }
        let lookup = try #require(StubURLProtocol.recordedRequests.first { $0.method == "GET" })
        #expect(lookup.queryParameters["date"] == "2026-11-11", "duplicates are checked on the planned day")
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["title"] as? String == "Workout")
        #expect(body["planned_date"] as? String == "2026-11-11")
        #expect(body["planned_start_time"] as? String == "8:00 AM")
        #expect(body["planned_duration_min"] as? Int == 45)
        #expect(body["task_category"] as? String == "Fitness/Health")
        #expect(body["total_tasks_today"] as? Int == 1)
        StubURLProtocol.reset()
    }

    @Test func backendFailuresUseTheServerDetail() async {
        StubURLProtocol.install { _ in .detail(503, "Primary database is not configured.") }

        await #expect(throws: PlanIntentError.backend("Primary database is not configured.")) {
            try await makeService().todaysPlans()
        }
        StubURLProtocol.reset()
    }
}

}
