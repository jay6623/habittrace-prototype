import Foundation

/// Overlap detection matching the PWA's `lib/scheduling.ts`.
///
/// Rules:
/// - Same calendar day only (compared by stored `"yyyy-MM-dd"` key).
/// - Half-open intervals `[start, start + duration)`, no buffer.
/// - Every task counts regardless of status, including completed ones.
/// - The task being edited is excluded.
/// - Tasks whose stored time cannot be parsed never conflict.
enum PlanOverlap {
    /// A proposed plan slot.
    struct Candidate: Equatable {
        let dateKey: String
        let startMinutes: Int
        let durationMinutes: Int
    }

    /// `[startA, startA + durationA)` intersects `[startB, startB + durationB)`.
    static func rangesOverlap(
        startA: Int, durationA: Int,
        startB: Int, durationB: Int
    ) -> Bool {
        startA < startB + durationB && startB < startA + durationA
    }

    /// Tasks on the candidate's day whose slot intersects it.
    static func conflicts(
        for candidate: Candidate,
        among tasks: [HabitTraceTask],
        excludingTaskID: String? = nil
    ) -> [HabitTraceTask] {
        tasks.filter { task in
            if let excludingTaskID, task.id == excludingTaskID {
                return false
            }

            guard
                task.plannedDate == candidate.dateKey,
                let start = task.startMinutes,
                let duration = task.plannedDurationMin
            else {
                return false
            }

            return rangesOverlap(
                startA: candidate.startMinutes,
                durationA: candidate.durationMinutes,
                startB: start,
                durationB: duration
            )
        }
    }
}
