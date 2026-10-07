import SwiftUI

/// Card-style task row used on Today and Plans.
///
/// Layout follows the PWA Plans row: start time and status dot on the
/// left, title with category chip, a meta line with duration and notes,
/// a status pill, and an optional action area supplied by the caller.
struct TaskRowView<Actions: View>: View {
    let task: HabitTraceTask
    var isActive = false
    @ViewBuilder var actions: Actions

    init(
        task: HabitTraceTask,
        isActive: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.task = task
        self.isActive = isActive
        self.actions = actions()
    }

    private var status: TaskDisplayStatus {
        TaskDisplayStatus(taskStatus: task.taskStatus, isActive: isActive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.md) {
                timeColumn

                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: HTSpacing.sm) {
                        Text(task.title)
                            .font(.htCardTitle)
                            .foregroundStyle(HTColor.textPrimary)
                            .strikethrough(status == .completed, color: HTColor.textMuted)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        if let category = task.taskCategory, !category.isEmpty {
                            CategoryChip(category: category)
                        }
                    }

                    metaLine

                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textSecondary)
                            .lineLimit(2)
                    }

                    StatusPill(status: status)
                        .padding(.top, HTSpacing.xs)
                }
            }

            actions
        }
        .htCard()
        .accessibilityElement(children: .contain)
    }

    private var timeColumn: some View {
        VStack(spacing: HTSpacing.xs) {
            Text(startTimeText)
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textStrong)
                .monospacedDigit()

            StatusDot(status: status)
        }
        .frame(minWidth: 56)
    }

    private var metaLine: some View {
        HTMetaText(durationText, dateText)
    }

    private var startTimeText: String {
        guard let time = task.plannedStartTime, !time.isEmpty else {
            return "—"
        }
        return TaskTimeFormatting.displayTime(time)
    }

    private var durationText: String {
        guard let minutes = task.plannedDurationMin else { return "" }
        return TaskTimeFormatting.durationText(minutes: minutes)
    }

    private var dateText: String {
        guard
            let stored = task.plannedDate,
            let date = TaskTimeFormatting.date(fromISODate: stored),
            !Calendar.current.isDateInToday(date)
        else {
            return ""
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension TaskRowView where Actions == EmptyView {
    init(task: HabitTraceTask, isActive: Bool = false) {
        self.init(task: task, isActive: isActive) { EmptyView() }
    }
}

#Preview("Task rows") {
    let pending = HabitTraceTask(
        id: "1",
        title: "Write project proposal",
        notes: "Outline the three main sections before drafting.",
        taskCategory: "Work",
        plannedDate: TaskTimeFormatting.isoDate(from: .now),
        plannedStartTime: "2:00 PM",
        plannedDurationMin: 45,
        importance: 4,
        energyLevel: 3,
        focusLevel: 4,
        taskStatus: "pending",
        createdAt: nil
    )

    let done = HabitTraceTask(
        id: "2",
        title: "Morning run",
        notes: nil,
        taskCategory: "Fitness/Health",
        plannedDate: "2026-10-06",
        plannedStartTime: "7:30 AM",
        plannedDurationMin: 30,
        importance: 3,
        energyLevel: 4,
        focusLevel: 2,
        taskStatus: "success",
        createdAt: nil
    )

    ScrollView {
        VStack(spacing: HTSpacing.md) {
            TaskRowView(task: pending) {
                HStack(spacing: HTSpacing.sm) {
                    Button("Start") {}
                        .buttonStyle(.htPrimary(fullWidth: true))
                    Button("Log outcome") {}
                        .buttonStyle(.htSecondary(fullWidth: true))
                }
            }

            TaskRowView(task: pending, isActive: true)

            TaskRowView(task: done)
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
