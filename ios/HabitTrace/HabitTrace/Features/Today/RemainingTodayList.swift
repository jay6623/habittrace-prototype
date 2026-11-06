import SwiftUI

/// "Remaining today" section: one card row per pending task, with the
/// PWA's Start and Log outcome actions.
struct RemainingTodayList: View {
    let tasks: [HabitTraceTask]
    /// Tasks with an active execution, shown as In progress.
    var runningTaskIDs: Set<String> = []
    let isBusy: Bool
    let onStart: (HabitTraceTask) -> Void
    let onLogOutcome: (HabitTraceTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HTSectionHeader("Remaining today") {
                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .monospacedDigit()
                }
            }

            if tasks.isEmpty {
                HTEmptyState(
                    title: "You're caught up",
                    message: "No more plans waiting for today."
                )
                .htCard()
            } else {
                ForEach(tasks) { task in
                    let isRunning = runningTaskIDs.contains(task.id)
                    TaskRowView(task: task, isActive: isRunning) {
                        HStack(spacing: HTSpacing.sm) {
                            if !isRunning {
                                Button("Start") {
                                    onStart(task)
                                }
                                .buttonStyle(.htPrimary(fullWidth: true))
                            }

                            Button("Log outcome") {
                                onLogOutcome(task)
                            }
                            .buttonStyle(.htSecondary(fullWidth: true))
                        }
                        .disabled(isBusy)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: HTSpacing.xl) {
            RemainingTodayList(
                tasks: Array(HabitTraceTask.previewTasks.prefix(2)),
                runningTaskIDs: [HabitTraceTask.previewTasks[1].id],
                isBusy: false,
                onStart: { _ in },
                onLogOutcome: { _ in }
            )

            RemainingTodayList(tasks: [], isBusy: false, onStart: { _ in }, onLogOutcome: { _ in })
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
