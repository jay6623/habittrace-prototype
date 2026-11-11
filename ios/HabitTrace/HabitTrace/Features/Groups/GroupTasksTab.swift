import SwiftUI

/// Tasks tab: filter menu and the list of shared tasks.
struct GroupTasksTab: View {
    @ObservedObject var viewModel: GroupsViewModel
    let onAddTask: () -> Void
    let onPlan: (GroupTask) -> Void
    let onCopy: (GroupTask) -> Void
    let onDelete: (GroupTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group tasks")
                        .htSectionTitle()
                    Text("Shared tasks assigned to team members")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
                Spacer(minLength: HTSpacing.sm)
                filterMenu
            }

            if viewModel.visibleTasks.isEmpty {
                VStack(spacing: HTSpacing.md) {
                    Text("No shared tasks match this view.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                    Button("+ Add the first task", action: onAddTask)
                        .buttonStyle(.htSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HTSpacing.md)
                .htCard()
            } else {
                ForEach(viewModel.visibleTasks) { task in
                    GroupTaskRow(
                        task: task,
                        viewModel: viewModel,
                        onPlan: onPlan,
                        onCopy: onCopy,
                        onDelete: onDelete
                    )
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $viewModel.assignmentFilter) {
                ForEach(GroupAssignmentFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            HStack(spacing: HTSpacing.xs) {
                Text(viewModel.assignmentFilter.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.htCaptionStrong)
            .foregroundStyle(HTColor.textStrong)
            .padding(.horizontal, HTSpacing.md)
            .frame(minHeight: 36)
            .background(HTColor.surfaceSecondary)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Filter tasks")
    }
}

/// One shared task: status dot, chips, due text, assignees with their
/// outcome controls, and the personal planning action.
struct GroupTaskRow: View {
    let task: GroupTask
    @ObservedObject var viewModel: GroupsViewModel
    let onPlan: (GroupTask) -> Void
    let onCopy: (GroupTask) -> Void
    let onDelete: (GroupTask) -> Void

    private var isBusy: Bool { viewModel.busyTaskID == task.id }

    private var deadlinePassed: Bool { viewModel.deadlinePassed(task) }

    private var canPlan: Bool { viewModel.isAssignedToMe(task) && !deadlinePassed }

    private var isFullyCompleted: Bool {
        !task.assignees.isEmpty
            && task.assignees.allSatisfy { viewModel.shownOutcome(for: task, assignee: $0) == .success }
    }

    private var dueText: String {
        var text = GroupHelpers.formatDue(task).map { "Due \($0)" } ?? "No due time"
        if let estimate = task.estimatedDurationMinutes {
            text += " · ~\(estimate) min"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.sm) {
                Circle()
                    .fill(isFullyCompleted ? HTColor.success400 : HTColor.borderStrong)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text(task.title)
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    HStack(spacing: HTSpacing.xs) {
                        CategoryChip(category: task.category)
                        GroupPill.priority(task.priority)
                    }
                    Text(dueText)
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }

                Spacer(minLength: HTSpacing.sm)

                Button {
                    onDelete(task)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HTColor.textMuted)
                        .frame(width: 32, height: 32)
                        .background(HTColor.surfaceSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("Delete \(task.title)")
            }

            assigneeList

            Button(canPlan ? "My prediction & plan" : "Copy to my plans") {
                if canPlan {
                    onPlan(task)
                } else {
                    onCopy(task)
                }
            }
            .buttonStyle(.htSecondary(fullWidth: true))
            .disabled(isBusy)
        }
        .htCard()
    }

    @ViewBuilder
    private var assigneeList: some View {
        if task.assignees.isEmpty {
            Text("Unassigned")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
        } else {
            VStack(spacing: HTSpacing.sm) {
                ForEach(task.assignees) { assignee in
                    assigneeRow(assignee)
                }
            }
        }
    }

    private func assigneeRow(_ assignee: GroupTaskAssignee) -> some View {
        let name = viewModel.memberName(assignee)
        let outcome = viewModel.shownOutcome(for: task, assignee: assignee)
        let isMine = assignee.userId == viewModel.currentUserID

        return HStack(spacing: HTSpacing.sm) {
            MemberAvatarView(name: name, avatarURL: assignee.avatarUrl, size: 24)
            Text(name)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: HTSpacing.sm)
            if isMine, !deadlinePassed {
                outcomeToggle(current: assignee.outcome)
            } else {
                Text(GroupHelpers.outcomeLabel(outcome))
                    .font(.htCaptionStrong)
                    .foregroundStyle(outcomeColor(outcome))
            }
        }
    }

    private func outcomeToggle(current: GroupOutcome?) -> some View {
        HStack(spacing: 0) {
            outcomeButton("Completed", outcome: .success, isActive: current == .success, activeColor: HTColor.success600)
            Rectangle()
                .fill(HTColor.border)
                .frame(width: 1, height: 20)
            outcomeButton("Not completed", outcome: .failed, isActive: current == .failed, activeColor: HTColor.danger600)
        }
        .background(HTColor.surface)
        .clipShape(.rect(cornerRadius: HTRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.sm, style: .continuous)
                .strokeBorder(HTColor.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status for \(task.title)")
    }

    private func outcomeButton(_ title: String, outcome: GroupOutcome, isActive: Bool, activeColor: Color) -> some View {
        Button(title) {
            guard !isActive else { return }
            Task { await viewModel.logCompletion(for: task, outcome: outcome) }
        }
        .font(.htCaptionStrong)
        .foregroundStyle(isActive ? .white : HTColor.textStrong)
        .padding(.horizontal, HTSpacing.sm)
        .frame(minHeight: 30)
        .background(isActive ? activeColor : HTColor.surface)
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func outcomeColor(_ outcome: GroupOutcome?) -> Color {
        switch outcome {
        case .success: HTColor.success700
        case .failed: HTColor.danger700
        case nil: HTColor.textMuted
        }
    }
}
