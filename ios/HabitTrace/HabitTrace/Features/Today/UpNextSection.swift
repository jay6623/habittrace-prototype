import SwiftUI

/// The dark hero area: the up-next task, a loading state, or an
/// empty state when nothing is pending.
///
/// Actions follow the PWA hero: Start and Log outcome for a pending
/// plan, Log outcome alone once the plan is running.
struct UpNextSection: View {
    let task: HabitTraceTask?
    /// Server-recorded start when `task` is running; drives the
    /// "In progress" treatment of the hero card.
    var activeSince: Date? = nil
    let hasTasksToday: Bool
    let isLoading: Bool
    let isBusy: Bool
    let onStart: (HabitTraceTask) -> Void
    let onLogOutcome: (HabitTraceTask) -> Void

    var body: some View {
        if let task {
            TaskHeroCard(task: task, activeSince: activeSince) {
                HStack(spacing: HTSpacing.md) {
                    if activeSince == nil {
                        Button("Start") {
                            onStart(task)
                        }
                        .buttonStyle(.htHeroPrimary)

                        Button("Log outcome") {
                            onLogOutcome(task)
                        }
                        .buttonStyle(.htHeroSecondary)
                    } else {
                        Button("Log outcome") {
                            onLogOutcome(task)
                        }
                        .buttonStyle(.htHeroPrimary)
                    }
                }
                .disabled(isBusy)
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
                isBusy: false,
                onStart: { _ in },
                onLogOutcome: { _ in }
            )

            UpNextSection(
                task: HabitTraceTask.previewTasks.first,
                activeSince: .now.addingTimeInterval(-1200),
                hasTasksToday: true,
                isLoading: false,
                isBusy: false,
                onStart: { _ in },
                onLogOutcome: { _ in }
            )

            UpNextSection(
                task: nil,
                hasTasksToday: false,
                isLoading: true,
                isBusy: false,
                onStart: { _ in },
                onLogOutcome: { _ in }
            )

            UpNextSection(
                task: nil,
                hasTasksToday: true,
                isLoading: false,
                isBusy: false,
                onStart: { _ in },
                onLogOutcome: { _ in }
            )
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
