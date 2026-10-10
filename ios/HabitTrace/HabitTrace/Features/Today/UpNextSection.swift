import SwiftUI

/// The dark hero area: the up-next task, a loading state, or an
/// empty state when nothing is pending.
struct UpNextSection: View {
    let task: HabitTraceTask?
    let hasTasksToday: Bool
    let isLoading: Bool
    let isCompleting: Bool
    let onComplete: (HabitTraceTask) -> Void

    var body: some View {
        if let task {
            TaskHeroCard(task: task) {
                Button {
                    onComplete(task)
                } label: {
                    if isCompleting {
                        ProgressView()
                            .tint(HTColor.ink)
                    } else {
                        Text("Mark complete")
                    }
                }
                .buttonStyle(.htHeroPrimary)
                .disabled(isCompleting)
            }
        } else if isLoading {
            TaskHeroEmptyCard(
                title: "Loading your day",
                message: "Fetching today's plans."
            ) {
                ProgressView()
                    .tint(.white)
            }
        } else if hasTasksToday {
            TaskHeroEmptyCard(
                title: "All done for today",
                message: "Every plan for today has been logged."
            ) {
                EmptyView()
            }
        } else {
            TaskHeroEmptyCard(
                title: "Nothing planned yet",
                message: "Use Quick Add to plan your next step."
            ) {
                EmptyView()
            }
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: HTSpacing.lg) {
            UpNextSection(
                task: HabitTraceTask.previewTasks.first,
                hasTasksToday: true,
                isLoading: false,
                isCompleting: false
            ) { _ in }

            UpNextSection(
                task: nil,
                hasTasksToday: false,
                isLoading: true,
                isCompleting: false
            ) { _ in }

            UpNextSection(
                task: nil,
                hasTasksToday: true,
                isLoading: false,
                isCompleting: false
            ) { _ in }

            UpNextSection(
                task: nil,
                hasTasksToday: false,
                isLoading: false,
                isCompleting: false
            ) { _ in }
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
