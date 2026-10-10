import Foundation

/// Actions a Plans row can offer, matching the PWA's buttons and menu.
enum PlanAction: Equatable {
    /// `POST /executions/start`. Pending plans that are not running.
    case start
    /// Opens the outcome sheet. Pending plans, running or not.
    case logOutcome
    /// Edits planning fields. Pending plans only.
    case edit
    /// Edits a recorded outcome. Completed or not-completed plans.
    case editLogged
    case delete
}

/// One displayed plan: the task joined with its active execution, if any.
///
/// Status derivation is shared with Today through `TaskDisplayStatus`,
/// where an active execution takes precedence over `task_status`.
struct PlanListItem: Identifiable, Equatable {
    let task: HabitTraceTask
    let activeExecution: HabitTraceExecution?

    var id: String { task.id }

    var isRunning: Bool {
        activeExecution != nil
    }

    var status: TaskDisplayStatus {
        TaskDisplayStatus(taskStatus: task.taskStatus, isActive: isRunning)
    }

    var isLogged: Bool {
        status.isLogged
    }

    var startMinutes: Int? {
        task.startMinutes
    }

    /// Actions available for this plan's current state.
    var availableActions: [PlanAction] {
        switch status {
        case .pending:
            [.start, .logOutcome, .edit, .delete]
        case .inProgress:
            [.logOutcome, .edit, .delete]
        case .completed, .notCompleted:
            [.editLogged, .delete]
        }
    }

    func supports(_ action: PlanAction) -> Bool {
        availableActions.contains(action)
    }
}

/// Deterministic ordering for plan lists.
///
/// The backend orders by the raw time string, which puts "10:00 AM"
/// before "9:00 AM". This sorts by parsed minutes, then title, then id,
/// with unparseable times after every timed task.
enum PlanOrdering {
    static func sorted(_ tasks: [HabitTraceTask]) -> [HabitTraceTask] {
        tasks.sorted { precedes($0, $1) }
    }

    static func precedes(_ lhs: HabitTraceTask, _ rhs: HabitTraceTask) -> Bool {
        let lhsMinutes = lhs.startMinutes ?? Int.max
        let rhsMinutes = rhs.startMinutes ?? Int.max

        if lhsMinutes != rhsMinutes {
            return lhsMinutes < rhsMinutes
        }

        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}

/// Counts for the Plans summary strip, derived from the same items the
/// list displays. Matches the PWA: `remaining` counts every pending plan,
/// including those in progress.
struct PlansSummary: Equatable {
    let total: Int
    let plannedMinutes: Int
    let completed: Int
    let inProgress: Int
    let remaining: Int
    let notCompleted: Int

    init(items: [PlanListItem]) {
        total = items.count
        plannedMinutes = items.reduce(0) { $0 + ($1.task.plannedDurationMin ?? 0) }
        completed = items.filter { $0.status == .completed }.count
        inProgress = items.filter { $0.status == .inProgress }.count
        remaining = items.filter { $0.status == .pending || $0.status == .inProgress }.count
        notCompleted = items.filter { $0.status == .notCompleted }.count
    }

    /// "30m", "1h", "2h 30m".
    var plannedDurationText: String {
        TaskTimeFormatting.compactDurationText(minutes: plannedMinutes)
    }
}

/// Why the list is empty, so the UI can show the right message.
enum PlansEmptyState: Equatable {
    /// No plans exist on the selected date.
    case noPlans
    /// Plans exist but none match the selected filter.
    case noMatches
}
