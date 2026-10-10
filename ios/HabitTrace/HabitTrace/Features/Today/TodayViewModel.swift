import Foundation

/// Derived, read-only presentation state for the Today screen.
///
/// Built from the shared task array on every render. All filtering is
/// client-side because the tasks endpoint is fetched without a date
/// filter. Nothing here performs network work.
struct TodayViewModel {
    /// Tasks whose `planned_date` is today.
    let todayTasks: [HabitTraceTask]
    /// Today's tasks marked `success`.
    let completedCount: Int
    /// Today's pending tasks, sorted by start time.
    let remainingTasks: [HabitTraceTask]
    /// Sum of `planned_duration_min` across today's tasks.
    let plannedMinutes: Int
    /// Pending tasks planned for a day before today.
    let unloggedCount: Int
    /// The pending task whose start time is closest to now.
    let upNext: HabitTraceTask?
    /// Remaining tasks with `upNext` removed, for the list below the hero.
    let remainingAfterUpNext: [HabitTraceTask]

    init(tasks: [HabitTraceTask], now: Date = .now, calendar: Calendar = .current) {
        let todayKey = TaskTimeFormatting.isoDate(from: now)
        let startOfToday = calendar.startOfDay(for: now)

        todayTasks = tasks.filter { $0.plannedDate == todayKey }

        completedCount = todayTasks.filter {
            TaskDisplayStatus(taskStatus: $0.taskStatus) == .completed
        }.count

        remainingTasks = todayTasks
            .filter { TaskDisplayStatus(taskStatus: $0.taskStatus) == .pending }
            .sorted { Self.startMinutes($0) < Self.startMinutes($1) }

        plannedMinutes = todayTasks.reduce(0) { $0 + ($1.plannedDurationMin ?? 0) }

        unloggedCount = tasks.filter { task in
            guard
                TaskDisplayStatus(taskStatus: task.taskStatus) == .pending,
                let stored = task.plannedDate,
                let day = TaskTimeFormatting.date(fromISODate: stored)
            else {
                return false
            }
            return day < startOfToday
        }.count

        let nextTask = Self.closestToNow(remainingTasks, now: now)
        let nextTaskID = nextTask?.id
        upNext = nextTask
        remainingAfterUpNext = remainingTasks.filter { $0.id != nextTaskID }
    }

    var hasTasksToday: Bool {
        !todayTasks.isEmpty
    }

    // MARK: - Helpers

    /// Minutes since midnight for sorting; unparseable times sort last.
    private static func startMinutes(_ task: HabitTraceTask) -> Int {
        guard let time = task.plannedStartTime else { return .max }
        return TaskTimeFormatting.minutesSinceMidnight(from: time) ?? .max
    }

    /// Mirrors the PWA: the pending task whose planned start is nearest
    /// to the current time, falling back to the first pending task.
    private static func closestToNow(_ tasks: [HabitTraceTask], now: Date) -> HabitTraceTask? {
        let scored: [(task: HabitTraceTask, distance: TimeInterval)] = tasks.compactMap { task in
            guard
                let start = TaskTimeFormatting.plannedStart(
                    date: task.plannedDate,
                    time: task.plannedStartTime
                )
            else {
                return nil
            }
            return (task, abs(start.timeIntervalSince(now)))
        }

        return scored.min { $0.distance < $1.distance }?.task ?? tasks.first
    }
}
