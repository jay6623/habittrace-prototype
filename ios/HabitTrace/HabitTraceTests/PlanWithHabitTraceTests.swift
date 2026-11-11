import Foundation
import Testing
@testable import HabitTrace

extension StubbedNetworkSuites {

/// The "Plan with HabitTrace" conversation: one sentence in, questions only
/// for what is missing, a read-back before saving, and nothing written on
/// cancel. Runs against the stubbed backend so the saved body is checked too.
@MainActor
@Suite
struct PlanWithHabitTraceFlowTests {
    private let calendar = Calendar.current
    // Tuesday 10 Nov 2026, 1:07 PM local time.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 13, minute: 7))!

    /// Answers the flow's questions from fixed values and records what was
    /// asked and what was read back for confirmation.
    @MainActor
    final class Script {
        var title: String?
        var startTime: Date?
        var duration: Int?
        var cancels = false

        private(set) var prompts: [String] = []
        private(set) var confirmation: String?

        var conversation: PlanConversation {
            PlanConversation(
                askTitle: { [self] prompt in
                    prompts.append(prompt)
                    return title ?? ""
                },
                askStartTime: { [self] prompt in
                    prompts.append(prompt)
                    return startTime
                },
                askDuration: { [self] prompt in
                    prompts.append(prompt)
                    return duration
                },
                confirm: { [self] summary in
                    confirmation = summary
                    if cancels { throw CancellationError() }
                }
            )
        }
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func spoken(_ date: Date) -> String {
        TaskTimeFormatting.displayTime(date)
    }

    private func makeService() -> PlanIntentService {
        PlanIntentService(
            taskService: TaskService(apiClient: APIClient(session: StubURLProtocol.makeSession())),
            tokenProvider: { "token" },
            now: { now }
        )
    }

    private func taskJSON(id: String, title: String, date: String, time: String, category: String = "Other", status: String = "pending") -> [String: Any] {
        [
            "id": id, "user_id": "u", "title": title, "task_category": category,
            "planned_date": date, "planned_start_time": time, "planned_duration_min": 30,
            "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1,
            "task_status": status, "created_at": "c",
        ]
    }

    /// Backend that has no plans yet and echoes creations.
    private func stubEmptyBackend(creating created: [String: Any]) {
        let body = StubURLProtocol.encode(created)
        StubURLProtocol.install { request in
            request.method == "POST" ? .json(201, body) : .json(200, StubURLProtocol.encode([[String: Any]]()))
        }
    }

    private func run(_ text: String, script: Script) async throws -> NaturalLanguagePlanOutcome {
        try await NaturalLanguagePlanFlow.run(
            request: text,
            now: now,
            calendar: calendar,
            defaultDuration: 30,
            conversation: script.conversation,
            service: makeService()
        )
    }

    // MARK: Complete sentences

    @Test func studyAlgorithmsNeedsNoQuestions() async throws {
        stubEmptyBackend(creating: taskJSON(id: "new", title: "Study algorithms", date: "2026-11-10", time: "5:00 PM", category: "Study"))
        let script = Script()

        let outcome = try await run("Study algorithms at 5 PM for 20 minutes.", script: script)

        #expect(script.prompts.isEmpty, "every field was in the sentence")
        #expect(script.confirmation == "Add “Study algorithms” today at \(spoken(date(11, 10, 17))) for 20 min under Study? I guessed the category.")
        guard case .created(let task) = outcome.result else { Issue.record("expected creation"); return }
        #expect(task.id == "new")

        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["title"] as? String == "Study algorithms")
        #expect(body["planned_date"] as? String == "2026-11-10")
        #expect(body["planned_start_time"] as? String == "5:00 PM")
        #expect(body["planned_duration_min"] as? Int == 20)
        #expect(body["task_category"] as? String == "Study")

        // Stated values are tagged as read from the sentence; the category
        // is a guess and the day a default.
        #expect(outcome.request.titleSource == .parsed)
        #expect(outcome.request.startSource == .parsed)
        #expect(outcome.request.durationSource == .parsed)
        #expect(outcome.request.categorySource == .inferred)
        #expect(outcome.request.daySource == .defaulted)
        StubURLProtocol.reset()
    }

    @Test func workoutTomorrowMorningAsksOnlyForTheTime() async throws {
        stubEmptyBackend(creating: taskJSON(id: "new", title: "Workout", date: "2026-11-11", time: "8:00 AM", category: "Fitness/Health"))
        let script = Script()
        script.startTime = date(11, 10, 8)  // Siri returns a time on today's date.

        let outcome = try await run("Workout tomorrow morning for 30 minutes.", script: script)

        #expect(script.prompts == ["What time in the morning should “Workout” start?"])
        #expect(script.confirmation == "Add “Workout” tomorrow at \(spoken(date(11, 11, 8))) for 30 min under Fitness & Health? I guessed the category.")
        guard case .created = outcome.result else { Issue.record("expected creation"); return }

        let lookup = try #require(StubURLProtocol.recordedRequests.first { $0.method == "GET" })
        #expect(lookup.queryParameters["date"] == "2026-11-11", "duplicates are checked on the planned day")
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["title"] as? String == "Workout")
        #expect(body["planned_date"] as? String == "2026-11-11", "the answered time keeps the spoken day")
        #expect(body["planned_start_time"] as? String == "8:00 AM")
        #expect(body["planned_duration_min"] as? Int == 30)
        #expect(body["task_category"] as? String == "Fitness/Health")

        #expect(outcome.request.daySource == .parsed)
        #expect(outcome.request.startSource == .explicit, "the time came from the follow-up answer")
        #expect(outcome.request.durationSource == .parsed)
        StubURLProtocol.reset()
    }

    // MARK: Missing or ambiguous time

    @Test func clockValueWithoutAMOrPMIsAskedAbout() async throws {
        stubEmptyBackend(creating: taskJSON(id: "new", title: "Call mom", date: "2026-11-10", time: "5:00 PM", category: "Social"))
        let script = Script()
        script.startTime = date(11, 10, 17)

        let outcome = try await run("Call mom at 5", script: script)

        #expect(script.prompts == ["What time should “Call mom” start? I heard “at 5” but not whether that's AM or PM."])
        #expect(script.confirmation == "Add “Call mom” today at \(spoken(date(11, 10, 17))) for 30 min under Social? 30 min is your default length. I guessed the category.")
        guard case .created = outcome.result else { Issue.record("expected creation"); return }
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        #expect(post.body?["planned_start_time"] as? String == "5:00 PM")
        StubURLProtocol.reset()
    }

    @Test func missingTimeWithNoAnswerSavesNothing() async {
        StubURLProtocol.install { _ in .detail(500, "should not be called") }
        let script = Script()  // no start time answer

        await #expect(throws: PlanIntentError.missingStartTime) {
            try await run("Add a study session", script: script)
        }

        #expect(script.prompts == ["What time should “Study session” start?"])
        #expect(script.confirmation == nil, "nothing is read back until the time is known")
        #expect(StubURLProtocol.recordedRequests.isEmpty)
        StubURLProtocol.reset()
    }

    @Test func emptyRequestAsksWhatToPlanThenWhen() async throws {
        stubEmptyBackend(creating: taskJSON(id: "new", title: "Read chapter 4", date: "2026-11-10", time: "9:00 PM", category: "Study"))
        let script = Script()
        script.title = "Read chapter 4"
        script.startTime = date(11, 10, 21)

        let outcome = try await run("", script: script)

        #expect(script.prompts == ["What would you like to plan?", "What time should “Read chapter 4” start?"])
        #expect(script.confirmation == "Add “Read chapter 4” today at \(spoken(date(11, 10, 21))) for 30 min under Study? 30 min is your default length. I guessed the category.")
        #expect(outcome.request.titleSource == .explicit)
        #expect(outcome.request.categorySource == .inferred, "the answered title still hints at a category")
        StubURLProtocol.reset()
    }

    @Test func cuesOnlySentenceKeepsItsDetailsWhileAskingForATitle() async throws {
        stubEmptyBackend(creating: taskJSON(id: "new", title: "Deep work", date: "2026-11-11", time: "5:00 PM"))
        let script = Script()
        script.title = "deep work"

        let outcome = try await run("5 PM for 20 minutes tomorrow", script: script)

        #expect(script.prompts == ["I have the details. What should I call this plan?"])
        #expect(outcome.request.title == "Deep work")
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["planned_date"] as? String == "2026-11-11")
        #expect(body["planned_start_time"] as? String == "5:00 PM")
        #expect(body["planned_duration_min"] as? Int == 20)
        StubURLProtocol.reset()
    }

    // MARK: Confirmation and cancellation

    @Test func cancellingTheReadBackSavesNothing() async {
        StubURLProtocol.install { _ in .detail(500, "should not be called") }
        let script = Script()
        script.cancels = true

        await #expect(throws: CancellationError.self) {
            try await run("Study algorithms at 5 PM for 20 minutes.", script: script)
        }

        #expect(script.confirmation?.hasPrefix("Add “Study algorithms” today at") == true)
        #expect(StubURLProtocol.recordedRequests.isEmpty, "the backend is not contacted before confirmation")
        StubURLProtocol.reset()
    }

    @Test func readBackHappensBeforeAnyNetworkCall() async throws {
        let order = OrderRecorder()
        StubURLProtocol.install { request in
            order.note("network \(request.method)")
            return request.method == "POST"
                ? .json(201, StubURLProtocol.encode(["id": "new", "user_id": "u", "title": "Yoga", "task_category": "Fitness/Health", "planned_date": "2026-11-10", "planned_start_time": "7:00 PM", "planned_duration_min": 30, "importance": 3, "energy_level": 3, "focus_level": 3, "total_tasks_today": 1, "task_status": "pending", "created_at": "c"] as [String: Any]))
                : .json(200, StubURLProtocol.encode([[String: Any]]()))
        }
        let conversation = PlanConversation(
            askTitle: { _ in "" },
            askStartTime: { _ in nil },
            askDuration: { _ in nil },
            confirm: { _ in order.note("confirm") }
        )

        _ = try await NaturalLanguagePlanFlow.run(
            request: "Yoga at 7 PM", now: now, calendar: calendar, defaultDuration: 30,
            conversation: conversation, service: makeService()
        )

        #expect(order.events == ["confirm", "network GET", "network POST"])
        StubURLProtocol.reset()
    }

    // MARK: Duplicate prevention

    @Test func duplicatesAreReportedNotRecreated() async throws {
        let existing = StubURLProtocol.encode([
            taskJSON(id: "dup", title: "Study algorithms", date: "2026-11-10", time: "5:00 PM", category: "Study"),
        ])
        StubURLProtocol.install { _ in .json(200, existing) }
        let script = Script()

        let outcome = try await run("study algorithms at 5pm for 20 minutes", script: script)

        guard case .duplicate(let task) = outcome.result else { Issue.record("expected duplicate"); return }
        #expect(task.id == "dup")
        #expect(script.confirmation != nil, "the read-back still happens; the duplicate is found when saving")
        #expect(StubURLProtocol.recordedRequests.count == 1)
        #expect(StubURLProtocol.recordedRequests.allSatisfy { $0.method == "GET" }, "no POST is sent for a duplicate")
        #expect(PlanIntentLogic.duplicateDialog(for: task, today: "2026-11-10") == "“Study algorithms” is already planned today at \(TaskTimeFormatting.displayTime("5:00 PM")), so I didn't add it again.")
        StubURLProtocol.reset()
    }

    // MARK: Backend validation

    @Test func backendRejectionIsSurfacedAfterConfirmation() async {
        StubURLProtocol.install { request in
            request.method == "POST" ? .detail(422, "planned_duration_min must be at least 5") : .json(200, StubURLProtocol.encode([[String: Any]]()))
        }
        let script = Script()

        await #expect(throws: PlanIntentError.backend("planned_duration_min must be at least 5")) {
            try await run("Yoga at 7 PM for 10 minutes", script: script)
        }
        #expect(script.confirmation != nil)
        StubURLProtocol.reset()
    }
}

}

/// Thread-safe event log for ordering assertions across the stub's
/// background queue and the main actor.
final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func note(_ event: String) {
        lock.withLock { storage.append(event) }
    }

    var events: [String] {
        lock.withLock { storage }
    }
}

/// The three intents stay registered as App Shortcuts; adding the
/// natural-language one must not remove or rename the existing entries.
struct HabitTraceShortcutsRegistrationTests {
    @Test func allThreeIntentsAreExposedAsAppShortcuts() {
        let shortcuts = HabitTraceShortcuts.appShortcuts
        #expect(shortcuts.count == 3)
    }
}
