import SwiftUI

/// Overview tab: per-member completion, the newest tasks, and the
/// destructive group actions the member's role allows.
struct GroupOverviewTab: View {
    @ObservedObject var viewModel: GroupsViewModel
    let onLeave: () -> Void
    let onDelete: () -> Void

    private var role: GroupRole? { viewModel.activeDetail?.group.role }

    var body: some View {
        VStack(spacing: HTSpacing.md) {
            completionCard
            recentCard

            if let role, role != .member {
                dangerCard(
                    title: "Delete group",
                    detail: "Removes the group and all of its shared tasks for every member.",
                    button: viewModel.isDeletingGroup ? "Deleting…" : "Delete this group",
                    action: onDelete
                )
            }

            if let role, role != .owner {
                dangerCard(
                    title: "Leave group",
                    detail: "You will lose access to this group and its shared tasks.",
                    button: viewModel.isDeletingGroup ? "Leaving…" : "Leave this group",
                    action: onLeave
                )
            }
        }
    }

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Task completion by member")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)

            ForEach(viewModel.members) { member in
                let progress = viewModel.stats.progressByMember[member.userId] ?? GroupStats.MemberProgress()
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HStack {
                        Text(viewModel.memberName(member))
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(progress.assigned > 0 ? "\(progress.done) / \(progress.assigned)" : "No tasks")
                            .font(.htCaptionStrong)
                            .foregroundStyle(HTColor.textPrimary)
                    }
                    GroupProgressBar(rate: progress.rate)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Recently added")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)

            if viewModel.tasks.isEmpty {
                Text("Nothing yet — add a group task to get started.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            } else {
                ForEach(viewModel.tasks.prefix(5)) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(task.title)”")
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textPrimary)
                        Text(assigneeSummary(task))
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func assigneeSummary(_ task: GroupTask) -> String {
        guard !task.assignees.isEmpty else { return "Unassigned" }
        return task.assignees.map { assignee in
            let word: String = switch viewModel.shownOutcome(for: task, assignee: assignee) {
            case .success: "completed"
            case .failed: "not completed"
            case nil: "not logged"
            }
            return "\(viewModel.memberName(assignee)) \(word)"
        }
        .joined(separator: ", ")
    }

    private func dangerCard(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text(title)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.danger700)
            Text(detail)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)
            Button(button, action: action)
                .buttonStyle(.htSecondary(fullWidth: true))
                .disabled(viewModel.isDeletingGroup)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(background: HTColor.danger50)
    }
}
