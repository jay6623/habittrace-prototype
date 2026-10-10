import SwiftUI

/// Pure layout for the Today screen.
///
/// Takes plain values and callbacks so it can be previewed with sample
/// tasks and composed by `TodayView`, which owns the service wiring.
struct TodayContentView: View {
    let tasks: [HabitTraceTask]
    let isLoading: Bool
    let loadErrorMessage: String?
    let greetingName: String?
    let isCompleting: Bool

    let onQuickAdd: () -> Void
    let onViewPlans: () -> Void
    let onReload: () async -> Void
    let onComplete: (HabitTraceTask) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let model = TodayViewModel(tasks: tasks, now: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.xl) {
                    TodayHeader(date: context.date, name: greetingName)

                    if let loadErrorMessage {
                        loadErrorCard(loadErrorMessage)
                    }

                    TodayStatsGrid(model: model)

                    PersonalizedOutlookCard(outlook: .sample)

                    UpNextSection(
                        task: model.upNext,
                        hasTasksToday: model.hasTasksToday,
                        isLoading: isLoading,
                        isCompleting: isCompleting,
                        onComplete: onComplete
                    )

                    Button("+ Quick Add", action: onQuickAdd)
                        .buttonStyle(.htOutline)

                    Button("View or reschedule plans", action: onViewPlans)
                        .buttonStyle(.htSecondary(fullWidth: true))

                    RemainingTodayList(
                        tasks: model.remainingAfterUpNext,
                        isCompleting: isCompleting,
                        onComplete: onComplete
                    )
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .refreshable {
                await onReload()
            }
        }
        .background(HTColor.surfaceMuted)
    }

    private func loadErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Label("Couldn't load today's plans", systemImage: "exclamationmark.triangle")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.danger700)

            Text(message)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            Button("Try again") {
                Task {
                    await onReload()
                }
            }
            .buttonStyle(.htSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(background: HTColor.danger50)
    }
}

#if DEBUG
#Preview("With plans") {
    TodayContentView(
        tasks: HabitTraceTask.previewTasks,
        isLoading: false,
        loadErrorMessage: nil,
        greetingName: "Yen",
        isCompleting: false,
        onQuickAdd: {},
        onViewPlans: {},
        onReload: {},
        onComplete: { _ in }
    )
    .askCoachOverlay {}
}

#Preview("Empty") {
    TodayContentView(
        tasks: [],
        isLoading: false,
        loadErrorMessage: nil,
        greetingName: nil,
        isCompleting: false,
        onQuickAdd: {},
        onViewPlans: {},
        onReload: {},
        onComplete: { _ in }
    )
}

#Preview("Load error") {
    TodayContentView(
        tasks: [],
        isLoading: false,
        loadErrorMessage: "The server returned HTTP 503.",
        greetingName: "Yen",
        isCompleting: false,
        onQuickAdd: {},
        onViewPlans: {},
        onReload: {},
        onComplete: { _ in }
    )
}
#endif
