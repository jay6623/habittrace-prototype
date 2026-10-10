import SwiftUI

/// "Remaining today" section: one card row per pending task.
struct RemainingTodayList: View {
    let tasks: [HabitTraceTask]
    let isCompleting: Bool
    let onComplete: (HabitTraceTask) -> Void

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
                    TaskRowView(task: task) {
                        Button("Mark complete") {
                            onComplete(task)
                        }
                        .buttonStyle(.htSecondary(fullWidth: true))
                        .disabled(isCompleting)
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
                isCompleting: false
            ) { _ in }

            RemainingTodayList(tasks: [], isCompleting: false) { _ in }
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
