import Foundation
import Testing
@testable import HabitTrace

// MARK: - Fixtures

private enum GroupFixtures {
    static let me = "user-me-000001"
    static let teammate = "user-tm-000002"
    static let kualaLumpur = TimeZone(identifier: "Asia/Kuala_Lumpur")!

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    static func task(
        id: String = "t1",
        assignees: [(String, String?)] = [],
        dueDate: String? = nil,
        dueTime: String? = nil,
        zone: String? = nil,
        priority: GroupTaskPriority = .medium,
        estimate: Int? = nil
    ) -> GroupTask {
        GroupTask(
            id: id,
            groupId: "g1",
            createdBy: me,
            assignedToIds: assignees.map(\.0),
            assignees: assignees.map { GroupTaskAssignee(userId: $0.0, displayName: nil, avatarUrl: nil, outcome: $0.1.flatMap(GroupOutcome.init(rawValue:))) },
            title: "Prepare slides",
            category: "Work",
            priority: priority,
            dueDate: dueDate,
            dueTime: dueTime,
            estimatedDurationMinutes: estimate,
            dueTimezoneName: zone,
            createdAt: "2026-09-01T00:00:00+00:00",
            updatedAt: "2026-09-01T00:00:00+00:00"
        )
    }

    static func member(_ id: String, role: String = "member") -> GroupMember {
        GroupMember(userId: id, role: GroupRole(rawValue: role)!, joinedAt: "2026-09-01T00:00:00+00:00", displayName: nil, avatarUrl: nil)
    }

    // JSON fixtures for the stubbed API.

    static func groupJSON(id: String = "g1", name: String = "Study Squad", role: String = "owner") -> [String: Any] {
        ["id": id, "owner_id": me, "name": name, "invite_code": "ABCD2345", "created_at": "2026-09-01T00:00:00+00:00", "role": role]
    }

    static func assigneeJSON(_ id: String, outcome: String?) -> [String: Any] {
        ["user_id": id, "display_name": id == me ? "Yen" : "Tam", "avatar_url": NSNull(), "outcome": outcome ?? NSNull()]
    }

    static func taskJSON(id: String, title: String, myOutcome: String?) -> [String: Any] {
        [
            "id": id, "group_id": "g1", "created_by": me, "assigned_to": NSNull(), "assignee_name": NSNull(),
            "assigned_to_ids": [me, teammate],
            "assignees": [assigneeJSON(me, outcome: myOutcome), assigneeJSON(teammate, outcome: "success")],
            "title": title, "category": "Work", "priority": "high", "status": "pending",
            "due_date": "2099-01-01", "due_time": "14:00:00", "estimated_duration_minutes": 45,
            "due_timezone_name": "Asia/Kuala_Lumpur",
            "created_at": "2026-09-01T00:00:00+00:00", "updated_at": "2026-09-01T00:00:00+00:00",
        ]
    }

    static func detailJSON(groupID: String = "g1", tasks: [[String: Any]]) -> [String: Any] {
        [
            "group": groupJSON(id: groupID),
            "members": [
                ["user_id": me, "role": "owner", "joined_at": "2026-09-01T00:00:00+00:00", "display_name": "Yen", "avatar_url": NSNull()],
                ["user_id": teammate, "role": "member", "joined_at": "2026-09-02T00:00:00+00:00", "display_name": "Tam", "avatar_url": NSNull()],
            ],
            "tasks": tasks,
        ]
    }

    @MainActor
    static func makeViewModel() -> GroupsViewModel {
        GroupsViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentUserID: me,
            accessTokenProvider: { "token" },
            defaults: UserDefaults(suiteName: "GroupsTests-\(UUID().uuidString)")!,
            timeZone: kualaLumpur
        )
    }
}

// MARK: - Pure helpers

@Suite
struct GroupHelpersTests {
    @Test func inviteCodesAreNormalizedAndValidated() {
        #expect(GroupHelpers.normalizeInviteCode(" ab-cd 12#34xyz") == "ABCD1234")
        #expect(GroupHelpers.normalizeInviteCode("héllo") == "HLLO")
        #expect(GroupHelpers.isValidInviteCode("ABCD1234"))
        #expect(!GroupHelpers.isValidInviteCode("abcd1234"))
        #expect(!GroupHelpers.isValidInviteCode("ABCD123"))
    }

    @Test func memberNameFallsBackToIDAndMarksYou() {
        #expect(GroupHelpers.memberName(displayName: "  Tam ", userID: "u2", currentUserID: "u1") == "Tam")
        #expect(GroupHelpers.memberName(displayName: nil, userID: "abcdef123", currentUserID: nil) == "Member abcdef")
        #expect(GroupHelpers.memberName(displayName: "", userID: "abcdef123", currentUserID: "abcdef123") == "Member abcdef (You)")
        #expect(GroupHelpers.memberInitial("tam") == "T")
        #expect(GroupHelpers.memberInitial("  ") == "?")
    }

    @Test func dueDateAndTimeFormatting() {
        #expect(GroupHelpers.formatDueDate("2026-09-07") == "Sep 7")
        #expect(GroupHelpers.formatDueDate("not-a-date") == "not-a-date")
        #expect(GroupHelpers.formatDueDate(nil) == nil)
        #expect(GroupHelpers.formatDueTime("14:00:00") == "2:00 PM")
        #expect(GroupHelpers.formatDueTime("00:05") == "12:05 AM")
        #expect(GroupHelpers.formatDueTime("12:30:00") == "12:30 PM")
        #expect(GroupHelpers.formatDueTime("garbage") == "garbage")

        let full = GroupFixtures.task(dueDate: "2026-09-07", dueTime: "14:00:00", zone: "Asia/Tokyo")
        #expect(GroupHelpers.formatDue(full) == "Sep 7 · 2:00 PM · Asia/Tokyo")
        #expect(GroupHelpers.formatDue(GroupFixtures.task(dueDate: "2026-09-07")) == "Sep 7")
        #expect(GroupHelpers.formatDue(GroupFixtures.task()) == nil)
    }

    @Test func deadlinePassedRespectsTheDeadlineZone() {
        let tokyo = GroupFixtures.task(dueDate: "2026-09-07", dueTime: "14:00:00", zone: "Asia/Tokyo")
        // 14:00 Tokyo is 05:00 UTC.
        #expect(GroupHelpers.deadlinePassed(tokyo, now: GroupFixtures.date("2026-09-07T04:59:00Z")) == false)
        #expect(GroupHelpers.deadlinePassed(tokyo, now: GroupFixtures.date("2026-09-07T05:00:00Z")) == true)

        let utc = TimeZone(secondsFromGMT: 0)!
        let noZone = GroupFixtures.task(dueDate: "2026-09-07", dueTime: "14:00")
        #expect(GroupHelpers.deadlinePassed(noZone, now: GroupFixtures.date("2026-09-07T13:59:00Z"), localTimeZone: utc) == false)
        #expect(GroupHelpers.deadlinePassed(noZone, now: GroupFixtures.date("2026-09-07T14:00:00Z"), localTimeZone: utc) == true)

        #expect(GroupHelpers.deadlinePassed(GroupFixtures.task(dueDate: "2000-01-01"), now: .now) == false)
    }

    @Test func shownOutcomePrefersLoggedThenDeadline() {
        let task = GroupFixtures.task(dueDate: "2026-09-07", dueTime: "14:00:00", zone: "Asia/Tokyo")
        let before = GroupFixtures.date("2026-09-07T04:00:00Z")
        let after = GroupFixtures.date("2026-09-07T06:00:00Z")
        #expect(GroupHelpers.shownOutcome(for: task, logged: .success, now: after) == .success)
        #expect(GroupHelpers.shownOutcome(for: task, logged: nil, now: after) == .failed)
        #expect(GroupHelpers.shownOutcome(for: task, logged: nil, now: before) == nil)
        #expect(GroupHelpers.outcomeLabel(nil) == "Not logged")
        #expect(GroupHelpers.outcomeLabel(.failed) == "Not completed")
    }

    @Test func statsDeriveFromShownOutcomes() {
        let me = GroupFixtures.me
        let tm = GroupFixtures.teammate
        let now = GroupFixtures.date("2026-09-08T00:00:00Z")
        let tasks = [
            GroupFixtures.task(id: "a", assignees: [(me, "success"), (tm, "failed")]),
            GroupFixtures.task(id: "b", assignees: [(me, nil), (tm, "success")]),
            // Deadline passed with nothing logged: counts as not completed.
            GroupFixtures.task(id: "c", assignees: [(me, nil)], dueDate: "2026-09-07", dueTime: "09:00:00", zone: "UTC"),
            GroupFixtures.task(id: "d"),
        ]
        let members = [GroupFixtures.member(me, role: "owner"), GroupFixtures.member(tm)]

        let stats = GroupStats.compute(tasks: tasks, members: members, currentUserID: me, now: now)

        #expect(stats.done == 2)
        #expect(stats.failed == 2)
        #expect(stats.loggedCount == 4)
        #expect(stats.successRate == 50)
        #expect(stats.assignedToMeUnlogged == 1)
        #expect(stats.progressByMember[me]?.assigned == 3)
        #expect(stats.progressByMember[me]?.done == 1)
        #expect(stats.progressByMember[me]?.rate == 33)
        #expect(stats.progressByMember[tm]?.rate == 50)
        #expect(GroupStats.compute(tasks: [], members: members, currentUserID: me).successRate == nil)
    }

    @Test func timestampsFormatInTheGivenZone() {
        let zone = GroupFixtures.kualaLumpur
        #expect(GroupHelpers.formatTimestamp("2026-09-07T06:30:00+00:00", timeZone: zone) == "Sep 7, 2:30 PM")
        #expect(GroupHelpers.formatTimestamp("2026-09-07T06:30:00.123456Z", timeZone: zone) == "Sep 7, 2:30 PM")
        #expect(GroupHelpers.formatTimestamp("2026-09-07T06:30:00", timeZone: zone) == "Sep 7, 2:30 PM")
        #expect(GroupHelpers.formatTimestamp("nope", timeZone: zone) == "nope")
        #expect(GroupHelpers.isoDate(from: GroupFixtures.date("2026-09-07T17:30:00Z"), timeZone: zone) == "2026-09-08")
    }

    @Test func personalPlanDraftBuildsOffsetISOStart() throws {
        let zone = GroupFixtures.kualaLumpur
        let task = GroupFixtures.task(estimate: 45)
        // 01:07 UTC is 09:07 in Kuala Lumpur; the next slot is 09:15.
        var draft = GroupPersonalPlanDraft.initial(for: task, now: GroupFixtures.date("2026-11-10T01:07:00Z"), timeZone: zone)
        #expect(draft.startMinutes == 9 * 60 + 15)
        #expect(draft.durationMinutes == 45)

        let request = try #require(draft.request(timeZone: zone))
        #expect(request.plannedStart == "2026-11-10T09:15:00+08:00")
        #expect(request.timezoneName == "Asia/Kuala_Lumpur")
        #expect(request.requiredEnergy == 3 && request.currentFocus == 3)

        let applied = draft.apply(candidateStart: "2026-11-10T06:00:00+00:00", timeZone: zone)
        #expect(applied)
        #expect(draft.startMinutes == 14 * 60)
        #expect(draft.request(timeZone: zone)?.plannedStart == "2026-11-10T14:00:00+08:00")
        let appliedGarbage = draft.apply(candidateStart: "later", timeZone: zone)
        #expect(!appliedGarbage)

        draft.durationMinutes = 0
        #expect(draft.request(timeZone: zone) == nil)
        #expect(GroupPersonalPlanDraft.levelLabel(1) == "1 — Low")
        #expect(GroupPersonalPlanDraft.levelLabel(3) == "3 — Moderate")
        #expect(GroupPersonalPlanDraft.levelLabel(5) == "5 — High")
        #expect(GroupPersonalPlanDraft.percent(0.726) == 73)
    }

    @MainActor
    @Test func copyDraftMapsPriorityAndEstimate() {
        let high = GroupFixtures.task(dueDate: "2026-09-07", dueTime: "14:00:00", priority: .high, estimate: 50)
        let draft = GroupsViewModel.copyDraft(for: high)
        #expect(draft.title == "Prepare slides")
        #expect(draft.importance == 5)
        #expect(draft.durationMinutes == 50)
        #expect(draft.startMinutes == 14 * 60)
        #expect(draft.category == .work)
        #expect(draft.dateKey == "2026-09-07")

        let low = GroupFixtures.task(priority: .low)
        #expect(GroupsViewModel.copyDraft(for: low).importance == 2)
        #expect(GroupsViewModel.copyDraft(for: low).durationMinutes == 30)
    }
}

// MARK: - View model (stubbed network)

extension StubbedNetworkSuites {

@MainActor
@Suite
struct GroupsViewModelTests {
    private func installListAndDetail(tasks: [[String: Any]] = []) {
        let list = StubURLProtocol.encode([GroupFixtures.groupJSON()])
        let detail = StubURLProtocol.encode(GroupFixtures.detailJSON(tasks: tasks))
        let none = StubURLProtocol.encode([])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/groups"): return .json(200, list)
            case ("GET", "/groups/g1"): return .json(200, detail)
            case ("GET", "/groups/g1/announcements"): return .json(200, none)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
    }

    @Test func loadsGroupsThenDetailWithTimezone() async throws {
        installListAndDetail(tasks: [GroupFixtures.taskJSON(id: "t1", title: "Slides", myOutcome: nil)])
        let viewModel = GroupFixtures.makeViewModel()

        await viewModel.loadGroups()

        #expect(viewModel.groupsError == nil)
        #expect(viewModel.isLoadingGroups == false)
        #expect(viewModel.groups.map(\.id) == ["g1"])
        #expect(viewModel.selectedGroupID == "g1")
        #expect(viewModel.activeDetail?.members.count == 2)
        #expect(viewModel.tasks.map(\.title) == ["Slides"])
        #expect(viewModel.stats.assignedToMeUnlogged == 1)
        #expect(viewModel.memberName(viewModel.members[0]) == "Yen (You)")

        let detailRequest = try #require(StubURLProtocol.recordedRequests.first { $0.path == "/groups/g1" })
        #expect(detailRequest.queryParameters["timezone"] == "Asia/Kuala_Lumpur")
        #expect(StubURLProtocol.recordedRequests.map(\.path) == ["/groups", "/groups/g1", "/groups/g1/announcements"])
        StubURLProtocol.reset()
    }

    @Test func createGroupSelectsItAndOpensInvite() async throws {
        let created = StubURLProtocol.encode(GroupFixtures.groupJSON(id: "g2", name: "Hackathon"))
        let detail = StubURLProtocol.encode(GroupFixtures.detailJSON(groupID: "g2", tasks: []))
        let none = StubURLProtocol.encode([])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/groups"): return .json(201, created)
            case ("GET", "/groups/g2"): return .json(200, detail)
            case ("GET", "/groups/g2/announcements"): return .json(200, none)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let viewModel = GroupFixtures.makeViewModel()

        try await viewModel.createGroup(name: "Hackathon")

        #expect(viewModel.groups.map(\.name) == ["Hackathon"])
        #expect(viewModel.selectedGroupID == "g2")
        #expect(viewModel.isShowingInvite)
        #expect(viewModel.isShowingSetup == false)
        #expect(viewModel.toast?.text == "Group created. Share the invite code with your team.")
        #expect(viewModel.activeDetail?.group.id == "g2")

        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        #expect(post.body?["name"] as? String == "Hackathon")
        StubURLProtocol.reset()
    }

    @Test func logCompletionSendsOutcomeAndReplacesTaskInPlace() async throws {
        let list = StubURLProtocol.encode([GroupFixtures.groupJSON()])
        let detail = StubURLProtocol.encode(GroupFixtures.detailJSON(tasks: [
            GroupFixtures.taskJSON(id: "t1", title: "Slides", myOutcome: nil),
            GroupFixtures.taskJSON(id: "t2", title: "Notes", myOutcome: nil),
        ]))
        let updated = StubURLProtocol.encode(GroupFixtures.taskJSON(id: "t2", title: "Notes", myOutcome: "success"))
        let none = StubURLProtocol.encode([])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/groups"): return .json(200, list)
            case ("GET", "/groups/g1"): return .json(200, detail)
            case ("GET", "/groups/g1/announcements"): return .json(200, none)
            case ("POST", "/groups/g1/tasks/t2/completion"): return .json(200, updated)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let viewModel = GroupFixtures.makeViewModel()
        await viewModel.loadGroups()
        let notes = try #require(viewModel.tasks.first { $0.id == "t2" })

        await viewModel.logCompletion(for: notes, outcome: .success)

        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        #expect(post.path == "/groups/g1/tasks/t2/completion")
        #expect(post.body?["outcome"] as? String == "success")
        #expect(post.body?["timezone"] as? String == "Asia/Kuala_Lumpur")
        #expect(viewModel.tasks.map(\.id) == ["t1", "t2"])
        #expect(viewModel.tasks[1].assignee(for: GroupFixtures.me)?.outcome == .success)
        #expect(viewModel.tasks[0].assignee(for: GroupFixtures.me)?.outcome == nil)
        #expect(viewModel.toast == nil)
        #expect(viewModel.busyTaskID == nil)

        // Tapping the already-active outcome is a no-op.
        let requestCount = StubURLProtocol.recordedRequests.count
        await viewModel.logCompletion(for: viewModel.tasks[1], outcome: .success)
        #expect(StubURLProtocol.recordedRequests.count == requestCount)
        StubURLProtocol.reset()
    }

    @Test func failedCompletionShowsToastAndReloads() async throws {
        let list = StubURLProtocol.encode([GroupFixtures.groupJSON()])
        let detail = StubURLProtocol.encode(GroupFixtures.detailJSON(tasks: [
            GroupFixtures.taskJSON(id: "t1", title: "Slides", myOutcome: nil),
        ]))
        let none = StubURLProtocol.encode([])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("GET", "/groups"): return .json(200, list)
            case ("GET", "/groups/g1"): return .json(200, detail)
            case ("GET", "/groups/g1/announcements"): return .json(200, none)
            case ("POST", "/groups/g1/tasks/t1/completion"): return .detail(422, "The scheduled time has passed.")
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let viewModel = GroupFixtures.makeViewModel()
        await viewModel.loadGroups()

        await viewModel.logCompletion(for: viewModel.tasks[0], outcome: .failed)

        #expect(viewModel.toast?.kind == .error)
        #expect(viewModel.toast?.text == "The scheduled time has passed.")
        let detailLoads = StubURLProtocol.recordedRequests.filter { $0.path == "/groups/g1" }
        #expect(detailLoads.count == 2)
        StubURLProtocol.reset()
    }

    @Test func personalPreviewAndConfirmSendTheReviewedInput() async throws {
        let preview = StubURLProtocol.encode([
            "prediction": [
                "model_version": "v2", "success_probability": 0.72, "base_success_probability": 0.65,
                "personalization": ["applied": true, "sample_count": 12, "confidence": 0.6, "history_success_rate": 0.7, "factors": []],
                "failure_reason_probabilities": ["schedule_overload": 0.4],
                "predicted_failure_reason": "schedule_overload",
                "recommended_actions": [["code": "shorter", "title": "Shorten it", "detail": "Try 30 minutes."]],
            ],
            "conflicts": [],
            "warnings": ["Close to the group deadline."],
            "candidates": [["planned_start": "2026-11-10T06:00:00+00:00", "success_probability": 0.8]],
            "personal_task": NSNull(),
        ])
        let created = StubURLProtocol.encode([
            "id": "p1", "title": "Prepare slides", "notes": NSNull(), "task_category": "Work",
            "planned_date": "2026-11-10", "planned_start_time": "9:15 AM", "planned_duration_min": 45,
            "importance": 3, "energy_level": 3, "focus_level": 3, "task_status": "pending",
            "created_at": "2026-11-10T00:00:00+00:00", "source_group_task_id": "t1",
        ])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/groups/g1/tasks/t1/personal-preview"): return .json(200, preview)
            case ("POST", "/groups/g1/tasks/t1/personal-plan"): return .json(201, created)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }
        let viewModel = GroupFixtures.makeViewModel()
        let task = GroupFixtures.task(estimate: 45)
        var draft = GroupPersonalPlanDraft.initial(for: task, now: GroupFixtures.date("2026-11-10T01:07:00Z"), timeZone: GroupFixtures.kualaLumpur)
        draft.requiredEnergy = 4
        draft.currentFocus = 2
        let input = try #require(draft.request(timeZone: GroupFixtures.kualaLumpur))

        let result = try await viewModel.previewPersonalPlan(for: task, input: input)
        #expect(result.prediction?.successProbability == 0.72)
        #expect(result.prediction?.personalization?.sampleCount == 12)
        #expect(result.prediction?.recommendedActions.first?.title == "Shorten it")
        #expect(result.warnings == ["Close to the group deadline."])
        #expect(result.candidates.first?.plannedStart == "2026-11-10T06:00:00+00:00")
        #expect(result.personalTask == nil)

        let plan = try await viewModel.confirmPersonalPlan(for: task, input: input)
        #expect(plan.id == "p1")
        #expect(plan.sourceGroupTaskId == "t1")
        #expect(viewModel.toast?.text == "Added to your personal plans.")

        let posts = StubURLProtocol.recordedRequests.filter { $0.method == "POST" }
        #expect(posts.map(\.path) == ["/groups/g1/tasks/t1/personal-preview", "/groups/g1/tasks/t1/personal-plan"])
        for post in posts {
            let body = try #require(post.body)
            #expect(body["planned_start"] as? String == "2026-11-10T09:15:00+08:00")
            #expect(body["planned_duration_minutes"] as? Int == 45)
            #expect(body["timezone_name"] as? String == "Asia/Kuala_Lumpur")
            #expect(body["required_energy"] as? Int == 4)
            #expect(body["required_focus"] as? Int == 3)
            #expect(body["current_energy"] as? Int == 3)
            #expect(body["current_focus"] as? Int == 2)
        }
        StubURLProtocol.reset()
    }

    @Test func createTaskPrependsAndSendsDueTimeAndZone() async throws {
        installListAndDetail(tasks: [GroupFixtures.taskJSON(id: "t1", title: "Slides", myOutcome: nil)])
        let viewModel = GroupFixtures.makeViewModel()
        await viewModel.loadGroups()

        let createdJSON = StubURLProtocol.encode(GroupFixtures.taskJSON(id: "t9", title: "Rehearse", myOutcome: nil))
        let list = StubURLProtocol.encode([GroupFixtures.groupJSON()])
        StubURLProtocol.install { request in
            switch (request.method, request.path) {
            case ("POST", "/groups/g1/tasks"): return .json(201, createdJSON)
            case ("GET", "/groups"): return .json(200, list)
            default: return .detail(500, "unexpected \(request.method) \(request.path)")
            }
        }

        let input = GroupTaskCreate(
            title: "Rehearse",
            category: "Work",
            priority: .high,
            dueDate: "2026-11-12",
            dueTime: "14:05",
            estimatedDurationMinutes: nil,
            dueTimezoneName: "Asia/Kuala_Lumpur",
            assignedToIds: [GroupFixtures.me]
        )
        try await viewModel.createTask(input)

        #expect(viewModel.tasks.map(\.id) == ["t9", "t1"])
        #expect(viewModel.toast?.text == "Task added for the group.")
        let post = try #require(StubURLProtocol.recordedRequests.first { $0.method == "POST" })
        let body = try #require(post.body)
        #expect(body["due_time"] as? String == "14:05")
        #expect(body["due_timezone_name"] as? String == "Asia/Kuala_Lumpur")
        #expect(body["assigned_to_ids"] as? [String] == [GroupFixtures.me])
        #expect(body["estimated_duration_minutes"] is NSNull)
        StubURLProtocol.reset()
    }
}

}
