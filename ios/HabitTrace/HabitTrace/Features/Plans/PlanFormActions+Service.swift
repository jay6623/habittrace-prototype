import Foundation

extension PlanFormActions {
    /// Create-only actions backed directly by the shared service, for
    /// screens without a `PlansViewModel` (Today, Calendar, Groups copy).
    /// Overlaps and `total_tasks_today` use a fresh fetch of the draft's day,
    /// as the PWA does.
    @MainActor
    static func creating(
        with taskService: TaskService,
        accessToken: @escaping @MainActor () async throws -> String
    ) -> PlanFormActions {
        PlanFormActions(
            overlappingPlans: { draft, excludingTaskID in
                let token = try await accessToken()
                let dayTasks = try await taskService.fetchTasks(accessToken: token, on: draft.dateKey)
                return PlanOverlap.conflicts(
                    for: draft.overlapCandidate,
                    among: dayTasks,
                    excludingTaskID: excludingTaskID
                )
            },
            save: { draft in
                do {
                    let token = try await accessToken()
                    let count = try await taskService.fetchTasks(accessToken: token, on: draft.dateKey).count
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
                        totalTasksToday: max(1, count + 1)
                    )
                    return .saved(created)
                } catch {
                    return .failed(ErrorPresentation.message(for: error))
                }
            },
            durationRecommendation: { draft, excludingTaskID in
                let token = try await accessToken()
                return try await taskService.durationRecommendation(
                    accessToken: token,
                    draft: draft,
                    excludingTaskID: excludingTaskID
                )
            }
        )
    }
}

extension TaskService {
    /// `GET /analytics/duration-recommendation` for a draft's title,
    /// category, and planned length.
    func durationRecommendation(
        accessToken: String,
        draft: PlanDraft,
        excludingTaskID: String?
    ) async throws -> DurationRecommendation {
        try await apiClient.fetchDurationRecommendation(
            accessToken: accessToken,
            title: draft.trimmedTitle,
            category: draft.category.rawValue,
            plannedMinutes: draft.durationMinutes,
            excludeTaskID: excludingTaskID
        )
    }
}
