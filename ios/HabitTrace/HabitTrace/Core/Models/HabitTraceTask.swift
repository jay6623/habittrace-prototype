import Foundation

/// A planned task, matching the backend's `TaskResponse`.
///
/// `plannedStartTime` is stored as text ("2:00 PM" or "14:00"); use
/// `TaskTimeFormatting` to parse it. `plannedDate` is "yyyy-MM-dd".
struct HabitTraceTask: Decodable, Identifiable, Equatable {
    let id: String
    let title: String

    let notes: String?
    let taskCategory: String?

    let plannedDate: String?
    let plannedStartTime: String?
    let plannedDurationMin: Int?

    let importance: Int?
    let energyLevel: Int?
    let focusLevel: Int?

    /// "pending", "success", or "failed".
    let taskStatus: String?
    let createdAt: String?

    // Additional contract fields. Declared as optional `var` so the
    // memberwise initializer keeps its existing call sites.
    var userId: String?
    var totalTasksToday: Int?
    var timezoneName: String?
    /// Present only once the server reports `aiSyncStatus` as "synced".
    var aiPlanInputId: String?
    /// "unlinked", "pending", or "synced".
    var aiSyncStatus: String?

    /// Minutes since midnight parsed from `plannedStartTime`, if valid.
    var startMinutes: Int? {
        guard let plannedStartTime else { return nil }
        return TaskTimeFormatting.minutesSinceMidnight(from: plannedStartTime)
    }

    /// A copy with a different `taskStatus`, used to mirror the server's
    /// status sync after an execution write without a full reload.
    func replacingStatus(_ status: String) -> HabitTraceTask {
        HabitTraceTask(
            id: id,
            title: title,
            notes: notes,
            taskCategory: taskCategory,
            plannedDate: plannedDate,
            plannedStartTime: plannedStartTime,
            plannedDurationMin: plannedDurationMin,
            importance: importance,
            energyLevel: energyLevel,
            focusLevel: focusLevel,
            taskStatus: status,
            createdAt: createdAt,
            userId: userId,
            totalTasksToday: totalTasksToday,
            timezoneName: timezoneName,
            aiPlanInputId: aiPlanInputId,
            aiSyncStatus: aiSyncStatus
        )
    }
}
