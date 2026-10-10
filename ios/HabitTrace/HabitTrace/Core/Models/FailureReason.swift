import Foundation

/// Canonical failure reason codes accepted by the backend (`FAILURE_REASONS`),
/// with the labels the PWA shows for each.
enum FailureReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case lowReadiness = "low_readiness"
    case scheduleOverload = "schedule_overload"
    case underestimatedTime = "underestimated_time"
    case interruption
    case unexpectedEvent = "unexpected_event"
    case unclearPlan = "unclear_plan"
    case taskTooDifficult = "task_too_difficult"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lowReadiness: "Low energy"
        case .scheduleOverload: "Too much scheduled"
        case .underestimatedTime: "Took longer than expected"
        case .interruption: "Got interrupted"
        case .unexpectedEvent: "Something unexpected came up"
        case .unclearPlan: "Unclear how to start"
        case .taskTooDifficult: "Harder than expected"
        case .other: "Other"
        }
    }
}
