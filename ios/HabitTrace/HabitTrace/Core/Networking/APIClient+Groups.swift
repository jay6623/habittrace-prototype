import Foundation

/// Group Scheduling endpoints under `/groups`. Membership is enforced
/// server-side: a group the caller does not belong to answers 404 on
/// every group-scoped route.
extension APIClient {
    // MARK: - Groups

    /// `GET /groups`: the caller's groups, oldest first.
    func fetchGroups(accessToken: String) async throws -> [GroupResponse] {
        let request = try makeRequest(.get, path: "groups", accessToken: accessToken)
        return try await send(request)
    }

    /// `POST /groups`. Returns the group with the caller as owner.
    func createGroup(accessToken: String, name: String) async throws -> GroupResponse {
        let request = try makeRequest(
            .post,
            path: "groups",
            body: GroupCreateRequest(name: name),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /groups/join`. 404 for an unknown code; 409 when already a member.
    func joinGroup(accessToken: String, inviteCode: String) async throws -> GroupResponse {
        let request = try makeRequest(
            .post,
            path: "groups/join",
            body: GroupJoinRequest(inviteCode: inviteCode),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `GET /groups/{id}?timezone=…`. The server also marks overdue,
    /// unlogged assignees as failed before answering.
    func fetchGroupDetail(accessToken: String, groupID: String, timezone: String) async throws -> GroupDetail {
        let request = try makeRequest(
            .get,
            path: "groups/\(groupID)",
            query: [URLQueryItem(name: "timezone", value: timezone)],
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `DELETE /groups/{id}`. Owner or admin only; returns 204.
    func deleteGroup(accessToken: String, groupID: String) async throws {
        let request = try makeRequest(.delete, path: "groups/\(groupID)", accessToken: accessToken)
        _ = try await perform(request)
    }

    /// `POST /groups/{id}/leave`. Admins and members only; returns 204.
    func leaveGroup(accessToken: String, groupID: String) async throws {
        var request = try makeRequest(.post, path: "groups/\(groupID)/leave", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    // MARK: - Members

    /// `PATCH /groups/{id}/members/{user_id}`. Owner only.
    func updateGroupMemberRole(
        accessToken: String,
        groupID: String,
        userID: String,
        role: GroupRole
    ) async throws -> GroupMember {
        let request = try makeRequest(
            .patch,
            path: "groups/\(groupID)/members/\(userID)",
            body: GroupMemberRoleUpdate(role: role),
            accessToken: accessToken
        )
        return try await send(request)
    }

    // MARK: - Announcements

    /// `GET /groups/{id}/announcements`: newest first, replies oldest first.
    func fetchGroupAnnouncements(accessToken: String, groupID: String) async throws -> [GroupAnnouncement] {
        let request = try makeRequest(.get, path: "groups/\(groupID)/announcements", accessToken: accessToken)
        return try await send(request)
    }

    /// `POST /groups/{id}/announcements`. Owner or admin only.
    func createGroupAnnouncement(
        accessToken: String,
        groupID: String,
        title: String,
        body: String
    ) async throws -> GroupAnnouncement {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/announcements",
            body: GroupAnnouncementCreate(title: title, body: body),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /groups/{id}/announcements/{aid}/replies`.
    func replyToGroupAnnouncement(
        accessToken: String,
        groupID: String,
        announcementID: String,
        body: String
    ) async throws -> GroupAnnouncementReply {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/announcements/\(announcementID)/replies",
            body: GroupReplyCreate(body: body),
            accessToken: accessToken
        )
        return try await send(request)
    }

    // MARK: - Tasks

    /// `POST /groups/{id}/tasks`. 422 when an assignee is not a member.
    func createGroupTask(accessToken: String, groupID: String, input: GroupTaskCreate) async throws -> GroupTask {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/tasks",
            body: input,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /groups/{id}/tasks/{tid}/completion`: logs the caller's own
    /// result. Assignees only; 422 once the scheduled time has passed.
    func logGroupTaskCompletion(
        accessToken: String,
        groupID: String,
        taskID: String,
        outcome: GroupOutcome,
        timezone: String
    ) async throws -> GroupTask {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/tasks/\(taskID)/completion",
            body: GroupTaskCompletionRequest(outcome: outcome, timezone: timezone),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `PATCH /groups/{id}/tasks/{tid}`: partial update.
    func updateGroupTask(
        accessToken: String,
        groupID: String,
        taskID: String,
        update: GroupTaskUpdate
    ) async throws -> GroupTask {
        let request = try makeRequest(
            .patch,
            path: "groups/\(groupID)/tasks/\(taskID)",
            body: update,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `DELETE /groups/{id}/tasks/{tid}`. Any member; returns 204.
    func deleteGroupTask(accessToken: String, groupID: String, taskID: String) async throws {
        let request = try makeRequest(.delete, path: "groups/\(groupID)/tasks/\(taskID)", accessToken: accessToken)
        _ = try await perform(request)
    }

    // MARK: - Personal planning

    /// `POST /groups/{id}/tasks/{tid}/personal-preview`. Assignees only.
    func previewGroupPersonalPlan(
        accessToken: String,
        groupID: String,
        taskID: String,
        input: GroupPersonalPlanRequest
    ) async throws -> GroupPersonalPreview {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/tasks/\(taskID)/personal-preview",
            body: input,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /groups/{id}/tasks/{tid}/personal-plan`: creates (or returns
    /// the existing) personal task. 409 when the time overlaps another plan.
    func confirmGroupPersonalPlan(
        accessToken: String,
        groupID: String,
        taskID: String,
        input: GroupPersonalPlanRequest
    ) async throws -> HabitTraceTask {
        let request = try makeRequest(
            .post,
            path: "groups/\(groupID)/tasks/\(taskID)/personal-plan",
            body: input,
            accessToken: accessToken
        )
        return try await send(request)
    }
}
