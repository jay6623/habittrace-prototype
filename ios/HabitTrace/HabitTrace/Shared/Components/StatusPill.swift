import SwiftUI

/// Display state of a task row, derived from the backend `task_status`
/// plus whether an execution is currently running.
enum TaskDisplayStatus: Equatable {
    case pending
    case inProgress
    case completed
    case notCompleted

    /// Maps a backend status string. `isActive` takes precedence so a
    /// started task shows as in progress even while still "pending".
    init(taskStatus: String?, isActive: Bool = false) {
        if isActive {
            self = .inProgress
            return
        }

        switch taskStatus?.lowercased() {
        case "success": self = .completed
        case "failed": self = .notCompleted
        default: self = .pending
        }
    }

    var label: String {
        switch self {
        case .pending: "Planned"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .notCompleted: "Not completed"
        }
    }

    var isLogged: Bool {
        self == .completed || self == .notCompleted
    }

    /// Dot color: pulsing emerald when active, emerald-400 success,
    /// rose-300 failed, slate-300 pending.
    var dotColor: Color {
        switch self {
        case .pending: HTColor.borderStrong
        case .inProgress: HTColor.success400
        case .completed: HTColor.success400
        case .notCompleted: HTColor.danger300
        }
    }

    var pillBackground: Color {
        switch self {
        case .pending: HTColor.surfaceSecondary
        case .inProgress: HTColor.success50
        case .completed: HTColor.success50
        case .notCompleted: HTColor.danger50
        }
    }

    var pillForeground: Color {
        switch self {
        case .pending: HTColor.textStrong
        case .inProgress: HTColor.success700
        case .completed: HTColor.success700
        case .notCompleted: HTColor.danger700
        }
    }
}

/// Rounded label such as "Planned" or "Completed".
struct StatusPill: View {
    let status: TaskDisplayStatus

    var body: some View {
        Text(status.label)
            .font(.htCaptionStrong)
            .foregroundStyle(status.pillForeground)
            .padding(.horizontal, HTSpacing.sm)
            .padding(.vertical, HTSpacing.xs)
            .background(status.pillBackground)
            .clipShape(Capsule())
    }
}

/// Small colored dot. Pulses while a task is in progress.
struct StatusDot: View {
    let status: TaskDisplayStatus
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size))
            .foregroundStyle(status.dotColor)
            .symbolEffect(.pulse, isActive: status == .inProgress)
            .accessibilityHidden(true)
    }
}

#Preview("Status") {
    VStack(alignment: .leading, spacing: HTSpacing.md) {
        ForEach(
            [TaskDisplayStatus.pending, .inProgress, .completed, .notCompleted],
            id: \.label
        ) { status in
            HStack(spacing: HTSpacing.md) {
                StatusDot(status: status)
                StatusPill(status: status)
            }
        }
    }
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
