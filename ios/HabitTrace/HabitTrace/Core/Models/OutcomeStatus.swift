import Foundation

/// Outcome of an execution, matching the backend's `OutcomeStatus` literal.
///
/// Server rules (enforced on every write):
/// - `completed` requires `task_status` "success" and `completion_ratio` 1.
/// - `partial` requires a `completion_ratio` strictly between 0 and 1.
/// - `abandoned` and `notStarted` force `completion_ratio` 0.
/// - `notStarted` may carry no actual times, interruptions, or activity.
/// - Any failed outcome other than `notStarted` requires a `FailureReason`.
enum OutcomeStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "not_started"
    case partial
    case completed
    case abandoned

    /// The `task_status` the backend expects alongside this outcome.
    var taskStatus: String {
        self == .completed ? "success" : "failed"
    }

    /// Whether the backend treats the plan as having ended before completion.
    var stoppedEarly: Bool {
        self == .partial || self == .abandoned
    }
}
