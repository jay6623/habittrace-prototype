import SwiftUI

/// One plan in the list: the shared `TaskRowView` plus the actions the
/// item's derived state allows. Availability comes from
/// `PlanListItem.availableActions`; this view only renders it.
struct PlanRow: View {
    let item: PlanListItem
    let isBusy: Bool
    /// True while this row's Start request is in flight.
    var isStarting = false
    let onAction: (PlanAction) -> Void

    var body: some View {
        TaskRowView(task: item.task, isActive: item.isRunning, showsDate: false) {
            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                if let activeSince {
                    HTMetaText("Active since \(TaskTimeFormatting.displayTime(activeSince))", color: HTColor.success700)
                }

                HStack(spacing: HTSpacing.sm) {
                    if item.supports(.start) {
                        Button {
                            onAction(.start)
                        } label: {
                            if isStarting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Start")
                            }
                        }
                        .buttonStyle(.htPrimary(fullWidth: true))
                        .accessibilityLabel(isStarting ? "Starting" : "Start")
                    }

                    if item.supports(.logOutcome) {
                        Button("Log outcome") {
                            onAction(.logOutcome)
                        }
                        .buttonStyle(.htSecondary(fullWidth: true))
                    }

                    if item.supports(.editLogged) {
                        Button("Edit logged outcome") {
                            onAction(.editLogged)
                        }
                        .buttonStyle(.htSecondary(fullWidth: true))
                    }

                    moreMenu
                }
                .disabled(isBusy)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if item.supports(.edit) {
                Button("Edit plan", systemImage: "pencil") {
                    onAction(.edit)
                }
            }

            if item.supports(.editLogged) {
                Button("Edit logged outcome", systemImage: "pencil") {
                    onAction(.editLogged)
                }
            }

            if item.supports(.delete) {
                Button("Delete plan", systemImage: "trash", role: .destructive) {
                    onAction(.delete)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(HTColor.textStrong)
                .frame(width: HTControlHeight.standard, height: HTControlHeight.standard)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions")
    }

    private var activeSince: Date? {
        guard let stamp = item.activeExecution?.actualStartTime else { return nil }
        return TaskTimeFormatting.date(fromISO8601: stamp)
    }
}

#if DEBUG
#Preview {
    let tasks = HabitTraceTask.previewTasks
    let running = HabitTraceExecution(
        id: "ex",
        taskId: tasks[1].id,
        userId: "u",
        actualStartTime: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-900)),
        actualEndTime: nil,
        interruptionCount: 0,
        stoppedEarly: false,
        taskStatus: nil,
        failureReason: nil,
        createdAt: "c"
    )

    ScrollView {
        VStack(spacing: HTSpacing.md) {
            PlanRow(item: PlanListItem(task: tasks[0], activeExecution: nil), isBusy: false) { _ in }
            PlanRow(item: PlanListItem(task: tasks[1], activeExecution: running), isBusy: false) { _ in }
            PlanRow(item: PlanListItem(task: tasks[2], activeExecution: nil), isBusy: false) { _ in }
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
