import Foundation

/// Status filter for the Plans list.
///
/// Matches the PWA's four filters plus an explicit In progress option.
/// `planned` follows the PWA: it is `task_status == "pending"`, which
/// includes plans that are currently running.
enum PlansFilter: String, CaseIterable, Identifiable {
    case all
    case planned
    case inProgress
    case completed
    case notCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All plans"
        case .planned: "Planned"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .notCompleted: "Not completed"
        }
    }

    func includes(_ status: TaskDisplayStatus) -> Bool {
        switch self {
        case .all: true
        case .planned: status == .pending || status == .inProgress
        case .inProgress: status == .inProgress
        case .completed: status == .completed
        case .notCompleted: status == .notCompleted
        }
    }
}
