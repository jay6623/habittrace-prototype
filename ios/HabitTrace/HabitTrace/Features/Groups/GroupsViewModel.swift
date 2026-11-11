import Combine
import Foundation

/// Which shared tasks the Tasks tab shows.
nonisolated enum GroupAssignmentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case mine
    case unassigned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Everyone’s tasks"
        case .mine: "Assigned to me"
        case .unassigned: "Unassigned"
        }
    }
}

/// State for the Groups tab: the member's groups, the selected group's
/// detail, announcements, and every mutation the page offers. Mirrors
/// `/dashboard/group` in the PWA, including its toast copy and the rule
/// that a passed deadline shows as "not completed".
@MainActor
final class GroupsViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String

    // MARK: Groups list

    @Published private(set) var groups: [GroupResponse] = []
    @Published private(set) var isLoadingGroups = true
    @Published private(set) var groupsError: String?
    @Published private(set) var selectedGroupID: String?

    // MARK: Selected group

    @Published private(set) var detail: GroupDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: String?
    @Published private(set) var busyTaskID: String?
    @Published private(set) var isDeletingGroup = false
    @Published private(set) var updatingMemberID: String?
    @Published var assignmentFilter: GroupAssignmentFilter = .all

    // MARK: Announcements

    @Published private(set) var announcements: [GroupAnnouncement] = []
    @Published private(set) var isLoadingAnnouncements = false
    @Published private(set) var announcementsError: String?

    // MARK: Page chrome

    @Published var toast: HTToastMessage?
    @Published var isShowingInvite = false
    @Published var isShowingSetup = false

    let currentUserID: String?
    let timeZone: TimeZone

    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider
    private let defaults: UserDefaults
    private var detailGeneration = 0
    private var announcementsGeneration = 0

    init(
        apiClient: APIClient = APIClient(),
        currentUserID: String?,
        accessTokenProvider: @escaping AccessTokenProvider,
        defaults: UserDefaults = .standard,
        timeZone: TimeZone = .current
    ) {
        self.apiClient = apiClient
        self.currentUserID = currentUserID
        self.accessTokenProvider = accessTokenProvider
        self.defaults = defaults
        self.timeZone = timeZone
    }

    // MARK: - Derived state

    var selectedGroup: GroupResponse? {
        groups.first { $0.id == selectedGroupID }
    }

    /// The loaded detail only when it belongs to the selected group.
    var activeDetail: GroupDetail? {
        guard let detail, detail.group.id == selectedGroupID else { return nil }
        return detail
    }

    var tasks: [GroupTask] { activeDetail?.tasks ?? [] }

    var members: [GroupMember] { activeDetail?.members ?? [] }

    /// Tasks matching the assignment filter.
    var visibleTasks: [GroupTask] {
        tasks.filter { task in
            switch assignmentFilter {
            case .all: true
            case .mine: currentUserID.map { task.assigneeIDs.contains($0) } ?? false
            case .unassigned: task.assigneeIDs.isEmpty
            }
        }
    }

    /// Completion counts and per-member progress for the selected group.
    var stats: GroupStats {
        GroupStats.compute(tasks: tasks, members: members, currentUserID: currentUserID)
    }

    var canPostAnnouncements: Bool {
        guard let role = activeDetail?.group.role else { return false }
        return role == .owner || role == .admin
    }

    func memberName(_ member: GroupMember) -> String {
        GroupHelpers.memberName(member, currentUserID: currentUserID)
    }

    func memberName(_ assignee: GroupTaskAssignee) -> String {
        GroupHelpers.memberName(assignee, currentUserID: currentUserID)
    }

    func authorName(id: String, name: String?) -> String {
        GroupHelpers.memberName(displayName: name, userID: id, currentUserID: currentUserID)
    }

    /// Whether the signed-in user is assigned to `task`.
    func isAssignedToMe(_ task: GroupTask) -> Bool {
        guard let currentUserID else { return false }
        return task.assigneeIDs.contains(currentUserID)
    }

    func deadlinePassed(_ task: GroupTask) -> Bool {
        GroupHelpers.deadlinePassed(task, localTimeZone: timeZone)
    }

    func shownOutcome(for task: GroupTask, assignee: GroupTaskAssignee) -> GroupOutcome? {
        GroupHelpers.shownOutcome(for: task, logged: assignee.outcome, localTimeZone: timeZone)
    }

    // MARK: - Loading

    /// Loads the group list and the detail of the resolved selection: the
    /// current selection if still present, else the stored one, else the
    /// first group.
    func loadGroups() async {
        isLoadingGroups = true
        groupsError = nil

        do {
            let token = try await accessTokenProvider()
            let list = try await apiClient.fetchGroups(accessToken: token)
            groups = list

            let resolved: String?
            if let current = selectedGroupID, list.contains(where: { $0.id == current }) {
                resolved = current
            } else if let stored = storedGroupID(), list.contains(where: { $0.id == stored }) {
                resolved = stored
            } else {
                resolved = list.first?.id
            }
            selectedGroupID = resolved
            isLoadingGroups = false

            if let resolved {
                await loadDetail(groupID: resolved)
            }
        } catch {
            isLoadingGroups = false
            if isCancellation(error) { return }
            groupsError = GroupHelpers.describeAPIError(error, fallback: "We couldn't load your groups.")
        }
    }

    /// Selects a group, remembers it for this account, and loads its detail.
    func select(groupID: String?) async {
        guard groupID != selectedGroupID || activeDetail == nil else { return }
        applySelection(groupID)
        if let groupID {
            await loadDetail(groupID: groupID)
        }
    }

    /// Reloads the selected group's detail.
    func reloadDetail() async {
        guard let selectedGroupID else { return }
        await loadDetail(groupID: selectedGroupID)
    }

    /// `GET /groups/{id}` with the device time zone. A 404 means the group
    /// was deleted or the member was removed since the list loaded.
    func loadDetail(groupID: String) async {
        detailGeneration += 1
        let generation = detailGeneration
        isLoadingDetail = true
        detailError = nil

        do {
            let token = try await accessTokenProvider()
            let loaded = try await apiClient.fetchGroupDetail(
                accessToken: token,
                groupID: groupID,
                timezone: timeZone.identifier
            )
            guard generation == detailGeneration else { return }
            detail = loaded
            isLoadingDetail = false
            await loadAnnouncements(groupID: groupID)
        } catch {
            guard generation == detailGeneration else { return }
            isLoadingDetail = false
            if isCancellation(error) { return }
            if (error as? APIError)?.statusCode == 404 {
                toast = .error("That group is no longer available.")
                applySelection(nil)
                detail = nil
                await loadGroups()
                return
            }
            detailError = GroupHelpers.describeAPIError(error, fallback: "We couldn't load this group.")
        }
    }

    // MARK: - Create / join

    /// Creates a group, selects it, and opens the invite panel. Throws so
    /// the sheet can show the mapped error inline.
    func createGroup(name: String) async throws {
        let token = try await accessTokenProvider()
        let created = try await apiClient.createGroup(accessToken: token, name: name)
        groups.append(created)
        applySelection(created.id)
        isShowingSetup = false
        isShowingInvite = true
        toast = .success("Group created. Share the invite code with your team.")
        await loadDetail(groupID: created.id)
    }

    /// Joins a group by invite code and selects it.
    func joinGroup(inviteCode: String) async throws {
        let token = try await accessTokenProvider()
        let joined = try await apiClient.joinGroup(accessToken: token, inviteCode: inviteCode)
        if !groups.contains(where: { $0.id == joined.id }) {
            groups.append(joined)
        }
        applySelection(joined.id)
        isShowingSetup = false
        toast = .success("You joined \(joined.name).")
        await loadDetail(groupID: joined.id)
    }

    // MARK: - Group lifecycle

    /// Deletes the selected group (owner or admin) and selects the first
    /// remaining one.
    func deleteSelectedGroup() async {
        guard let group = selectedGroup, !isDeletingGroup else { return }
        isDeletingGroup = true
        defer { isDeletingGroup = false }

        do {
            let token = try await accessTokenProvider()
            try await apiClient.deleteGroup(accessToken: token, groupID: group.id)
            await removeGroupLocally(group)
            toast = .success("\(group.name) was deleted.")
        } catch {
            toast = .error(GroupHelpers.describeAPIError(error, fallback: "We couldn't delete this group."))
        }
    }

    /// Leaves the selected group (admin or member) and selects the first
    /// remaining one.
    func leaveSelectedGroup() async {
        guard let group = selectedGroup, !isDeletingGroup else { return }
        isDeletingGroup = true
        defer { isDeletingGroup = false }

        do {
            let token = try await accessTokenProvider()
            try await apiClient.leaveGroup(accessToken: token, groupID: group.id)
            await removeGroupLocally(group)
            toast = .success("You left \(group.name).")
        } catch {
            toast = .error(GroupHelpers.describeAPIError(error, fallback: "We couldn't leave this group."))
        }
    }

    private func removeGroupLocally(_ group: GroupResponse) async {
        groups.removeAll { $0.id == group.id }
        detail = nil
        announcements = []
        let next = groups.first?.id
        applySelection(next)
        if let next {
            await loadDetail(groupID: next)
        }
    }

    // MARK: - Members

    /// Promotes or demotes a member (owner only).
    func setRole(_ role: GroupRole, for member: GroupMember) async {
        guard let groupID = selectedGroupID, updatingMemberID == nil else { return }
        updatingMemberID = member.userId
        defer { updatingMemberID = nil }

        do {
            let token = try await accessTokenProvider()
            let updated = try await apiClient.updateGroupMemberRole(
                accessToken: token,
                groupID: groupID,
                userID: member.userId,
                role: role
            )
            if var current = detail, current.group.id == groupID,
               let index = current.members.firstIndex(where: { $0.userId == member.userId }) {
                current.members[index].role = updated.role
                detail = current
            }
            let name = memberName(member)
            toast = .success(role == .admin ? "\(name) is now an admin." : "\(name) is now a member.")
        } catch {
            toast = .error(GroupHelpers.describeAPIError(error, fallback: "We couldn't update this member's role."))
        }
    }

    // MARK: - Tasks

    /// Creates a shared task and prepends it. Throws so the form can show
    /// the mapped error inline.
    func createTask(_ input: GroupTaskCreate) async throws {
        guard let groupID = selectedGroupID else { return }
        let token = try await accessTokenProvider()
        let created = try await apiClient.createGroupTask(accessToken: token, groupID: groupID, input: input)
        if var current = detail, current.group.id == groupID {
            current.tasks.insert(created, at: 0)
            detail = current
        }
        toast = .success("Task added for the group.")
    }

    /// Logs the signed-in assignee's result. Tapping the already-active
    /// outcome is a no-op; failures reload the detail so the row matches
    /// the server.
    func logCompletion(for task: GroupTask, outcome: GroupOutcome) async {
        guard busyTaskID == nil else { return }
        guard let mine = task.assignee(for: currentUserID), mine.outcome != outcome else { return }
        busyTaskID = task.id
        defer { busyTaskID = nil }

        do {
            let token = try await accessTokenProvider()
            let updated = try await apiClient.logGroupTaskCompletion(
                accessToken: token,
                groupID: task.groupId,
                taskID: task.id,
                outcome: outcome,
                timezone: timeZone.identifier
            )
            replaceTask(updated)
        } catch {
            toast = .error(GroupHelpers.describeAPIError(error, fallback: "We couldn't log that task."))
            if let selectedGroupID {
                await loadDetail(groupID: selectedGroupID)
            }
        }
    }

    /// Deletes a shared task for every member.
    func deleteTask(_ task: GroupTask) async {
        guard busyTaskID == nil else { return }
        busyTaskID = task.id
        defer { busyTaskID = nil }

        do {
            let token = try await accessTokenProvider()
            try await apiClient.deleteGroupTask(accessToken: token, groupID: task.groupId, taskID: task.id)
            if var current = detail, current.group.id == task.groupId {
                current.tasks.removeAll { $0.id == task.id }
                detail = current
            }
        } catch {
            toast = .error(GroupHelpers.describeAPIError(error, fallback: "We couldn't delete that task."))
        }
    }

    private func replaceTask(_ next: GroupTask) {
        guard var current = detail, current.group.id == next.groupId,
              let index = current.tasks.firstIndex(where: { $0.id == next.id }) else { return }
        current.tasks[index] = next
        detail = current
    }

    // MARK: - Personal planning

    /// Previews the member's private plan for a shared task.
    func previewPersonalPlan(for task: GroupTask, input: GroupPersonalPlanRequest) async throws -> GroupPersonalPreview {
        let token = try await accessTokenProvider()
        return try await apiClient.previewGroupPersonalPlan(
            accessToken: token,
            groupID: task.groupId,
            taskID: task.id,
            input: input
        )
    }

    /// Adds the reviewed plan to the member's personal plans.
    @discardableResult
    func confirmPersonalPlan(for task: GroupTask, input: GroupPersonalPlanRequest) async throws -> HabitTraceTask {
        let token = try await accessTokenProvider()
        let created = try await apiClient.confirmGroupPersonalPlan(
            accessToken: token,
            groupID: task.groupId,
            taskID: task.id,
            input: input
        )
        toast = .success("Added to your personal plans.")
        return created
    }

    /// Prefilled personal draft for "Copy to my plans": the due date (or
    /// today), the due time (or the next quarter hour), the estimate (or
    /// 30 minutes), a known category (else Other), and priority mapped
    /// high → 5, low → 2, else 3.
    static func copyDraft(for task: GroupTask, now: Date = .now, calendar: Calendar = .current) -> PlanDraft {
        var draft = PlanDraft.new(on: now, now: now, calendar: calendar)
        if let dueDate = task.dueDate, let date = TaskTimeFormatting.date(fromISODate: dueDate) {
            draft.plannedDate = calendar.startOfDay(for: date)
        }
        if let dueTime = task.dueTime, let minutes = TaskTimeFormatting.minutesSinceMidnight(from: String(dueTime.prefix(5))) {
            draft.startMinutes = minutes
        }
        draft.title = task.title
        draft.durationMinutes = task.estimatedDurationMinutes ?? 30
        draft.category = TaskCategory.allCases.first { $0.rawValue == task.category } ?? .other
        draft.importance = switch task.priority {
        case .high: 5
        case .low: 2
        case .medium: 3
        }
        return draft
    }

    /// Toast shown once a personal copy has been created.
    func personalCopyCreated() {
        toast = .success("Personal copy created. Changes to this copy do not update the group task.")
    }

    // MARK: - Announcements

    func loadAnnouncements(groupID: String) async {
        announcementsGeneration += 1
        let generation = announcementsGeneration
        isLoadingAnnouncements = true
        announcementsError = nil

        do {
            let token = try await accessTokenProvider()
            let loaded = try await apiClient.fetchGroupAnnouncements(accessToken: token, groupID: groupID)
            guard generation == announcementsGeneration else { return }
            announcements = loaded
        } catch {
            guard generation == announcementsGeneration else { return }
            if isCancellation(error) { return }
            announcementsError = GroupHelpers.describeAPIError(error, fallback: "We couldn't load announcements.")
        }
        isLoadingAnnouncements = false
    }

    /// Posts an announcement (owner or admin) and prepends it.
    func postAnnouncement(title: String, body: String) async throws {
        guard let groupID = selectedGroupID else { return }
        let token = try await accessTokenProvider()
        let created = try await apiClient.createGroupAnnouncement(
            accessToken: token,
            groupID: groupID,
            title: title,
            body: body
        )
        announcements.insert(created, at: 0)
    }

    /// Replies in a thread and appends the reply locally.
    func postReply(to announcement: GroupAnnouncement, body: String) async throws {
        let token = try await accessTokenProvider()
        let reply = try await apiClient.replyToGroupAnnouncement(
            accessToken: token,
            groupID: announcement.groupId,
            announcementID: announcement.id,
            body: body
        )
        if let index = announcements.firstIndex(where: { $0.id == announcement.id }) {
            announcements[index].replies.append(reply)
        }
    }

    /// Clears the announcements error, for example when a form is dismissed.
    func clearAnnouncementsError() {
        announcementsError = nil
    }

    // MARK: - Selection persistence

    private func applySelection(_ groupID: String?) {
        selectedGroupID = groupID
        isShowingInvite = false
        guard let currentUserID else { return }
        let key = GroupHelpers.selectedGroupStorageKey(userID: currentUserID)
        if let groupID {
            defaults.set(groupID, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func storedGroupID() -> String? {
        guard let currentUserID else { return nil }
        return defaults.string(forKey: GroupHelpers.selectedGroupStorageKey(userID: currentUserID))
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
