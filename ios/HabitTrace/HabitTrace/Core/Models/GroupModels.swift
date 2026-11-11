import Foundation

// MARK: - Enumerations

/// A member's role in a group. Mirrors `GroupRole` in `backend/app/schemas/group.py`.
nonisolated enum GroupRole: String, Codable, Equatable, Sendable {
    case owner
    case admin
    case member
}

/// Aggregate status of a shared task.
nonisolated enum GroupTaskStatus: String, Codable, Equatable, Sendable {
    case pending
    case success
    case failed
}

/// Priority of a shared task. Raw values are shown lower-case in the UI.
nonisolated enum GroupTaskPriority: String, Codable, Equatable, CaseIterable, Sendable {
    case low
    case medium
    case high

    /// Capitalized label used by the task form.
    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// One assignee's logged result for a shared task.
nonisolated enum GroupOutcome: String, Codable, Equatable, Sendable {
    case success
    case failed
}

// MARK: - Wire models

/// `GroupResponse`: one group with the caller's role in it.
nonisolated struct GroupResponse: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var ownerId: String
    var name: String
    var inviteCode: String
    var createdAt: String
    /// The signed-in user's role in this group.
    var role: GroupRole
}

/// `GroupMemberResponse`.
nonisolated struct GroupMember: Codable, Equatable, Identifiable, Sendable {
    var userId: String
    var role: GroupRole
    var joinedAt: String
    var displayName: String?
    var avatarUrl: String?

    var id: String { userId }
}

/// `GroupTaskAssigneeResponse`: one assignee and their logged outcome.
nonisolated struct GroupTaskAssignee: Codable, Equatable, Identifiable, Sendable {
    var userId: String
    var displayName: String?
    var avatarUrl: String?
    var outcome: GroupOutcome?

    var id: String { userId }
}

/// `GroupTaskResponse`. `dueDate` is "YYYY-MM-DD"; `dueTime` is "HH:MM:SS".
nonisolated struct GroupTask: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var groupId: String
    var createdBy: String
    var assignedTo: String?
    var assigneeName: String?
    var assignedToIds: [String]
    var assignees: [GroupTaskAssignee]
    var title: String
    var category: String
    var priority: GroupTaskPriority
    var status: GroupTaskStatus
    var dueDate: String?
    var dueTime: String?
    var estimatedDurationMinutes: Int?
    var dueTimezoneName: String?
    var createdAt: String
    var updatedAt: String

    init(
        id: String,
        groupId: String,
        createdBy: String,
        assignedTo: String? = nil,
        assigneeName: String? = nil,
        assignedToIds: [String] = [],
        assignees: [GroupTaskAssignee] = [],
        title: String,
        category: String,
        priority: GroupTaskPriority = .medium,
        status: GroupTaskStatus = .pending,
        dueDate: String? = nil,
        dueTime: String? = nil,
        estimatedDurationMinutes: Int? = nil,
        dueTimezoneName: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.groupId = groupId
        self.createdBy = createdBy
        self.assignedTo = assignedTo
        self.assigneeName = assigneeName
        self.assignedToIds = assignedToIds
        self.assignees = assignees
        self.title = title
        self.category = category
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.dueTimezoneName = dueTimezoneName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Lists default to empty when the server omits them.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupId = try container.decode(String.self, forKey: .groupId)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        assignedTo = try container.decodeIfPresent(String.self, forKey: .assignedTo)
        assigneeName = try container.decodeIfPresent(String.self, forKey: .assigneeName)
        assignedToIds = try container.decodeIfPresent([String].self, forKey: .assignedToIds) ?? []
        assignees = try container.decodeIfPresent([GroupTaskAssignee].self, forKey: .assignees) ?? []
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        priority = try container.decode(GroupTaskPriority.self, forKey: .priority)
        status = try container.decode(GroupTaskStatus.self, forKey: .status)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        dueTime = try container.decodeIfPresent(String.self, forKey: .dueTime)
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        dueTimezoneName = try container.decodeIfPresent(String.self, forKey: .dueTimezoneName)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    /// Assignee ids, falling back to the legacy single `assignedTo` field.
    /// Mirrors the PWA's `taskAssigneeIds`.
    var assigneeIDs: [String] {
        if !assignedToIds.isEmpty {
            return assignedToIds
        }
        if let assignedTo {
            return [assignedTo]
        }
        return []
    }

    /// The assignee entry for `userID`, if any.
    func assignee(for userID: String?) -> GroupTaskAssignee? {
        guard let userID else { return nil }
        return assignees.first { $0.userId == userID }
    }
}

/// `GroupDetailResponse`: members by join time, tasks newest first.
nonisolated struct GroupDetail: Codable, Equatable, Sendable {
    var group: GroupResponse
    var members: [GroupMember]
    var tasks: [GroupTask]
}

/// A reply inside an announcement thread.
nonisolated struct GroupAnnouncementReply: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var announcementId: String
    var groupId: String
    var authorId: String
    var authorName: String?
    var authorRole: GroupRole?
    var authorAvatarUrl: String?
    var body: String
    var createdAt: String
}

/// An announcement with its replies, oldest reply first.
nonisolated struct GroupAnnouncement: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var groupId: String
    var authorId: String
    var authorName: String?
    var authorRole: GroupRole?
    var authorAvatarUrl: String?
    var title: String
    var body: String
    var createdAt: String
    var replies: [GroupAnnouncementReply]

    init(
        id: String,
        groupId: String,
        authorId: String,
        authorName: String? = nil,
        authorRole: GroupRole? = nil,
        authorAvatarUrl: String? = nil,
        title: String,
        body: String,
        createdAt: String,
        replies: [GroupAnnouncementReply] = []
    ) {
        self.id = id
        self.groupId = groupId
        self.authorId = authorId
        self.authorName = authorName
        self.authorRole = authorRole
        self.authorAvatarUrl = authorAvatarUrl
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupId = try container.decode(String.self, forKey: .groupId)
        authorId = try container.decode(String.self, forKey: .authorId)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        authorRole = try container.decodeIfPresent(GroupRole.self, forKey: .authorRole)
        authorAvatarUrl = try container.decodeIfPresent(String.self, forKey: .authorAvatarUrl)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        replies = try container.decodeIfPresent([GroupAnnouncementReply].self, forKey: .replies) ?? []
    }
}

// MARK: - Personal planning

/// `GroupPersonalPlanRequest`: the member's private schedule for a shared
/// task. `plannedStart` is ISO-8601 with offset on a whole minute.
nonisolated struct GroupPersonalPlanRequest: Codable, Equatable, Sendable {
    var plannedStart: String
    var plannedDurationMinutes: Int
    var timezoneName: String
    var requiredEnergy: Int = 3
    var requiredFocus: Int = 3
    var currentEnergy: Int = 3
    var currentFocus: Int = 3
}

/// An alternative start on the same day with its estimated success.
nonisolated struct GroupPersonalCandidate: Codable, Equatable, Sendable {
    var plannedStart: String
    var successProbability: Double
}

/// `GroupPersonalPreview`: prediction, calendar conflicts, warnings, and
/// alternative times for a member's private plan. `personalTask` is set
/// when the member already added this shared task to their plans.
///
/// Main-actor isolated like `HabitTraceTask`, which it embeds.
struct GroupPersonalPreview: Decodable, Equatable {
    var prediction: AIPredictResponse?
    var conflicts: [String]
    var warnings: [String]
    var candidates: [GroupPersonalCandidate]
    var personalTask: HabitTraceTask?

    private enum CodingKeys: String, CodingKey {
        case prediction, conflicts, warnings, candidates, personalTask
    }

    init(
        prediction: AIPredictResponse? = nil,
        conflicts: [String] = [],
        warnings: [String] = [],
        candidates: [GroupPersonalCandidate] = [],
        personalTask: HabitTraceTask? = nil
    ) {
        self.prediction = prediction
        self.conflicts = conflicts
        self.warnings = warnings
        self.candidates = candidates
        self.personalTask = personalTask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prediction = try container.decodeIfPresent(AIPredictResponse.self, forKey: .prediction)
        conflicts = try container.decodeIfPresent([String].self, forKey: .conflicts) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        candidates = try container.decodeIfPresent([GroupPersonalCandidate].self, forKey: .candidates) ?? []
        personalTask = try container.decodeIfPresent(HabitTraceTask.self, forKey: .personalTask)
    }
}

// MARK: - Request bodies

/// `POST /groups`.
nonisolated struct GroupCreateRequest: Encodable, Equatable, Sendable {
    var name: String
}

/// `POST /groups/join`.
nonisolated struct GroupJoinRequest: Encodable, Equatable, Sendable {
    var inviteCode: String
}

/// `PATCH /groups/{id}/members/{user_id}`.
nonisolated struct GroupMemberRoleUpdate: Encodable, Equatable, Sendable {
    var role: GroupRole
}

/// `POST /groups/{id}/announcements`.
nonisolated struct GroupAnnouncementCreate: Encodable, Equatable, Sendable {
    var title: String
    var body: String
}

/// `POST /groups/{id}/announcements/{aid}/replies`.
nonisolated struct GroupReplyCreate: Encodable, Equatable, Sendable {
    var body: String
}

/// `POST /groups/{id}/tasks`. Optional fields are sent as explicit nulls,
/// matching the PWA; `dueTime` is "HH:MM".
nonisolated struct GroupTaskCreate: Encodable, Equatable, Sendable {
    var title: String
    var category: String
    var priority: GroupTaskPriority
    var dueDate: String?
    var dueTime: String?
    var estimatedDurationMinutes: Int?
    var dueTimezoneName: String
    var assignedToIds: [String]

    private enum CodingKeys: String, CodingKey {
        case title, category, priority, dueDate, dueTime, estimatedDurationMinutes, dueTimezoneName, assignedToIds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(dueTime, forKey: .dueTime)
        try container.encode(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encode(dueTimezoneName, forKey: .dueTimezoneName)
        try container.encode(assignedToIds, forKey: .assignedToIds)
    }
}

/// `PATCH /groups/{id}/tasks/{tid}`: only non-nil fields are sent.
nonisolated struct GroupTaskUpdate: Encodable, Equatable, Sendable {
    var title: String?
    var category: String?
    var priority: GroupTaskPriority?
    var status: GroupTaskStatus?
    var dueDate: String?
    var dueTime: String?
    var estimatedDurationMinutes: Int?
    var dueTimezoneName: String?
    var assignedToIds: [String]?
}

/// `POST /groups/{id}/tasks/{tid}/completion`.
nonisolated struct GroupTaskCompletionRequest: Encodable, Equatable, Sendable {
    var outcome: GroupOutcome
    var timezone: String
}

// MARK: - Derived statistics

/// Counts the Groups page derives from a detail response, using the
/// "shown outcome" rule (a passed deadline counts as not completed).
nonisolated struct GroupStats: Equatable, Sendable {
    struct MemberProgress: Equatable, Sendable {
        var assigned = 0
        var done = 0

        /// Whole-number completion percentage, nil without assignments.
        var rate: Int? {
            guard assigned > 0 else { return nil }
            return Int((Double(done) / Double(assigned) * 100).rounded())
        }
    }

    var done = 0
    var failed = 0
    /// Tasks where the current user is an assignee with no shown outcome.
    var assignedToMeUnlogged = 0
    var progressByMember: [String: MemberProgress] = [:]

    var loggedCount: Int { done + failed }

    /// Success percentage over logged outcomes, nil when nothing is logged.
    var successRate: Int? {
        guard loggedCount > 0 else { return nil }
        return Int((Double(done) / Double(loggedCount) * 100).rounded())
    }

    static func compute(
        tasks: [GroupTask],
        members: [GroupMember],
        currentUserID: String?,
        now: Date = .now
    ) -> GroupStats {
        var stats = GroupStats()
        for member in members {
            stats.progressByMember[member.userId] = MemberProgress()
        }

        for task in tasks {
            for assignee in task.assignees {
                let outcome = GroupHelpers.shownOutcome(for: task, logged: assignee.outcome, now: now)
                switch outcome {
                case .success: stats.done += 1
                case .failed: stats.failed += 1
                case nil: break
                }

                if var progress = stats.progressByMember[assignee.userId] {
                    progress.assigned += 1
                    if outcome == .success { progress.done += 1 }
                    stats.progressByMember[assignee.userId] = progress
                }

                if assignee.userId == currentUserID, outcome == nil {
                    stats.assignedToMeUnlogged += 1
                }
            }
        }
        return stats
    }
}

// MARK: - Helpers (port of `lib/group.ts`)

/// Pure presentation helpers for Group Scheduling.
nonisolated enum GroupHelpers {
    static let inviteCodeLength = 8
    static let groupNameMaxLength = 80
    static let taskTitleMaxLength = 200
    static let announcementTitleMaxLength = 120
    static let announcementBodyMaxLength = 2000

    /// Uppercase, drop anything that is not A–Z or 0–9, cap at 8 characters.
    static func normalizeInviteCode(_ raw: String) -> String {
        let allowed = raw.uppercased().unicodeScalars.filter { scalar in
            (65...90).contains(scalar.value) || (48...57).contains(scalar.value)
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: allowed.prefix(inviteCodeLength))
        return String(view)
    }

    /// True when `code` matches `^[A-Z0-9]{8}$`.
    static func isValidInviteCode(_ code: String) -> Bool {
        code.count == inviteCodeLength && normalizeInviteCode(code) == code
    }

    /// Display name, or "Member " + first six characters of the id, with
    /// " (You)" appended for the signed-in user.
    static func memberName(displayName: String?, userID: String, currentUserID: String?) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? "Member \(userID.prefix(6))" : trimmed
        return userID == currentUserID ? "\(base) (You)" : base
    }

    static func memberName(_ member: GroupMember, currentUserID: String?) -> String {
        memberName(displayName: member.displayName, userID: member.userId, currentUserID: currentUserID)
    }

    static func memberName(_ assignee: GroupTaskAssignee, currentUserID: String?) -> String {
        memberName(displayName: assignee.displayName, userID: assignee.userId, currentUserID: currentUserID)
    }

    /// First character of the name, uppercased, or "?".
    static func memberInitial(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// "2026-09-07" → "Sep 7". Parsed by parts so no time zone can shift
    /// the day; unparseable input is returned unchanged.
    static func formatDueDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: "-").map { Int($0) }
        guard
            parts.count == 3,
            let year = parts[0], let month = parts[1], let day = parts[2],
            year > 0, (1...12).contains(month), day > 0
        else {
            return value
        }
        return "\(monthAbbreviations[month - 1]) \(day)"
    }

    /// "14:00:00" → "2:00 PM". Unparseable input is returned unchanged.
    static func formatDueTime(_ value: String?) -> String? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard
            parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else {
            return value
        }
        let suffix = hour >= 12 ? "PM" : "AM"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):" + String(format: "%02d", minute) + " \(suffix)"
    }

    /// Date and time joined with " · ", plus the deadline's time zone when
    /// either part exists. Nil when the task has no due date or time.
    static func formatDue(_ task: GroupTask) -> String? {
        var parts = [formatDueDate(task.dueDate), formatDueTime(task.dueTime)].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        if let zone = task.dueTimezoneName, !zone.isEmpty {
            parts.append(zone)
        }
        return parts.joined(separator: " · ")
    }

    /// "HH:MM" → "HH:MM:00"; longer values pass through.
    private static func paddedTime(_ time: String) -> String {
        time.count == 5 ? "\(time):00" : time
    }

    private static func wallClockFormatter(in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }

    /// Whether the shared deadline is already behind `now`.
    ///
    /// False without both a due date and time. With a deadline time zone the
    /// comparison is made on wall-clock strings in that zone; without one
    /// the deadline is read in `localTimeZone` (the device zone).
    static func deadlinePassed(
        _ task: GroupTask,
        now: Date = .now,
        localTimeZone: TimeZone = .current
    ) -> Bool {
        guard let dueDate = task.dueDate, let dueTime = task.dueTime else { return false }
        let deadline = "\(dueDate)T\(paddedTime(dueTime))"

        if let zoneName = task.dueTimezoneName, let zone = TimeZone(identifier: zoneName) {
            return wallClockFormatter(in: zone).string(from: now) >= deadline
        }

        guard let deadlineDate = wallClockFormatter(in: localTimeZone).date(from: deadline) else {
            return false
        }
        return now >= deadlineDate
    }

    /// The outcome to display: the logged one, else "failed" once the
    /// deadline has passed, else nil ("Not logged").
    static func shownOutcome(
        for task: GroupTask,
        logged outcome: GroupOutcome?,
        now: Date = .now,
        localTimeZone: TimeZone = .current
    ) -> GroupOutcome? {
        if let outcome { return outcome }
        return deadlinePassed(task, now: now, localTimeZone: localTimeZone) ? .failed : nil
    }

    /// Label for a shown outcome: "Completed", "Not completed", or "Not logged".
    static func outcomeLabel(_ outcome: GroupOutcome?) -> String {
        switch outcome {
        case .success: "Completed"
        case .failed: "Not completed"
        case nil: "Not logged"
        }
    }

    /// Parses a server timestamp such as "2026-09-07T14:30:00+00:00", with
    /// or without fractional seconds; a value without an offset is read as UTC.
    static func date(fromTimestamp value: String) -> Date? {
        if let date = TaskTimeFormatting.date(fromISO8601: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    /// "Sep 7, 2:30 PM" in `timeZone`; unparseable input is returned unchanged.
    static func formatTimestamp(_ value: String, timeZone: TimeZone = .current) -> String {
        guard let date = date(fromTimestamp: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "yyyy-MM-dd" for `date` as seen in `timeZone`.
    static func isoDate(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Turns a thrown error into copy a person can act on. Backend `detail`
    /// strings are written for end users, so they are shown when present;
    /// validation arrays were already flattened by `APIClient`.
    static func describeAPIError(_ error: Error, fallback: String) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpStatus(let code, let detail):
                let message = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                switch code {
                case 401: return "Your session has expired. Please sign in again."
                case 403: return message.isEmpty ? "Only the group owner can do that." : message
                case 503: return "The server is temporarily unavailable. Try again shortly."
                default: return message.isEmpty ? fallback : message
                }
            case .invalidResponse, .decoding:
                return fallback
            }
        }

        if error is URLError {
            return "We couldn't connect. Check your network and try again."
        }

        return fallback
    }

    /// `UserDefaults` key remembering the last selected group per account.
    static func selectedGroupStorageKey(userID: String) -> String {
        "habittrace.group.selected.\(userID)"
    }
}
