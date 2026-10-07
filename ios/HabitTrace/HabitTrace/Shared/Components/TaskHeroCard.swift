import SwiftUI

/// Dark "Up next" / "In progress" card from the Today screen.
///
/// Shows an eyebrow, an optional pulsing "Active since" pill, the task
/// title, a meta line, and caller-supplied action buttons.
struct TaskHeroCard<Actions: View>: View {
    let task: HabitTraceTask
    var activeSince: Date?
    @ViewBuilder var actions: Actions

    init(
        task: HabitTraceTask,
        activeSince: Date? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.task = task
        self.activeSince = activeSince
        self.actions = actions()
    }

    private var isActive: Bool {
        activeSince != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.lg) {
            HStack(alignment: .center) {
                HTEyebrowLabel(
                    text: isActive ? "In progress" : "Up next",
                    color: .white.opacity(0.6)
                )

                Spacer()

                if let activeSince {
                    activePill(since: activeSince)
                }
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text(task.title)
                    .font(.htHeroTitle)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                HTMetaText(
                    startTimeText,
                    durationText,
                    task.taskCategory ?? "",
                    color: .white.opacity(0.7)
                )
            }

            actions
        }
        .htHeroCard()
        .accessibilityElement(children: .contain)
    }

    private func activePill(since date: Date) -> some View {
        HStack(spacing: HTSpacing.xs) {
            StatusDot(status: .inProgress, size: 8)

            Text("Active since \(TaskTimeFormatting.displayTime(date))")
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.success300)
        }
        .padding(.horizontal, HTSpacing.sm)
        .padding(.vertical, HTSpacing.xs)
        .background(HTColor.success600.opacity(0.25))
        .clipShape(Capsule())
    }

    private var startTimeText: String {
        guard let time = task.plannedStartTime, !time.isEmpty else { return "" }
        return TaskTimeFormatting.displayTime(time)
    }

    private var durationText: String {
        guard let minutes = task.plannedDurationMin else { return "" }
        return TaskTimeFormatting.durationText(minutes: minutes)
    }
}

/// Hero card shown when nothing is planned or everything is done.
struct TaskHeroEmptyCard<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.lg) {
            HTEyebrowLabel(text: "Up next", color: .white.opacity(0.6))

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text(title)
                    .font(.htHeroTitle)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.htBody)
                    .foregroundStyle(.white.opacity(0.7))
            }

            actions
        }
        .htHeroCard()
    }
}

#Preview("Hero cards") {
    let task = HabitTraceTask(
        id: "1",
        title: "Review lecture notes for Thursday's exam",
        notes: nil,
        taskCategory: "Study",
        plannedDate: TaskTimeFormatting.isoDate(from: .now),
        plannedStartTime: "3:30 PM",
        plannedDurationMin: 60,
        importance: 5,
        energyLevel: 3,
        focusLevel: 5,
        taskStatus: "pending",
        createdAt: nil
    )

    ScrollView {
        VStack(spacing: HTSpacing.lg) {
            TaskHeroCard(task: task) {
                HStack(spacing: HTSpacing.md) {
                    Button("Start") {}
                        .buttonStyle(.htHeroPrimary)
                    Button("Finish") {}
                        .buttonStyle(.htHeroSecondary)
                }
            }

            TaskHeroCard(task: task, activeSince: .now.addingTimeInterval(-1200)) {
                Button("Finish") {}
                    .buttonStyle(.htHeroPrimary)
            }

            TaskHeroEmptyCard(
                title: "Nothing planned yet",
                message: "Add a plan to see what's next."
            ) {
                Button("+ Quick Add") {}
                    .buttonStyle(.htHeroPrimary)
            }
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
