import SwiftUI

/// "Generate day" entry. Resolves the shared services from the environment
/// and hands them to `GenerateDayScreen`, which owns the view model.
struct GenerateDayView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    let initialDate: Date
    let draftID: String?
    /// Shown as a "Cancel" button on the form when provided.
    let onCancel: (() -> Void)?

    init(initialDate: Date = .now, draftID: String? = nil, onCancel: (() -> Void)? = nil) {
        self.initialDate = initialDate
        self.draftID = draftID
        self.onCancel = onCancel
    }

    var body: some View {
        GenerateDayScreen(
            taskService: taskService,
            accessTokenProvider: authManager.validAccessToken,
            preferences: authManager.planningPreferences,
            initialDate: initialDate,
            draftID: draftID,
            onCancel: onCancel
        )
    }
}

/// Mirrors `/dashboard/scheduler/generate`: a task form that becomes a
/// draft timeline with adjustable times and a confirm panel.
struct GenerateDayScreen: View {
    @StateObject private var viewModel: GenerateDayViewModel
    let onCancel: (() -> Void)?

    init(
        taskService: TaskService,
        accessTokenProvider: @escaping GenerateDayViewModel.AccessTokenProvider,
        preferences: PlanningPreferences,
        initialDate: Date,
        draftID: String?,
        onCancel: (() -> Void)?
    ) {
        _viewModel = StateObject(
            wrappedValue: GenerateDayViewModel(
                taskService: taskService,
                accessTokenProvider: accessTokenProvider,
                preferences: preferences,
                initialDate: initialDate,
                draftID: draftID
            )
        )
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HTSpacing.md) {
                if let result = viewModel.result {
                    draftContent(result)
                } else if viewModel.isLoadingDraft {
                    Text("Loading your draft…")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .htCard()
                } else {
                    formContent
                }
            }
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.top, HTSpacing.screenTop)
            .padding(.bottom, HTSpacing.screenBottom)
        }
        .background(HTColor.surfaceMuted)
        .scrollDismissesKeyboard(.interactively)
        .htToast($viewModel.toast)
        .task { await viewModel.loadDraftIfNeeded() }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                HTEyebrowLabel(text: "Daily Schedule Generator", color: HTColor.success700)
                Text("Generate today's plan")
                    .htPageTitle()
                Text("Add what you need to do without choosing times. HabitTrace will build a realistic draft around your existing plans and calendar.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
            }

            if let error = viewModel.errorMessage {
                AuthNotice(text: error, tone: .error)
            }

            daySettings

            HStack(alignment: .top, spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks to place")
                        .htSectionTitle()
                    Text("Title, category, duration, and importance help the AI choose a better time.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
                Spacer(minLength: HTSpacing.sm)
                Button("+ Add task") { viewModel.addTask() }
                    .buttonStyle(.htSecondary)
            }

            ForEach($viewModel.form.tasks) { $task in
                taskCard($task)
            }

            HStack(spacing: HTSpacing.sm) {
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.htSecondary)
                }
                Spacer(minLength: 0)
                Button(viewModel.isBusy ? "Building your day…" : "Generate draft schedule") {
                    Task { await viewModel.generate() }
                }
                .buttonStyle(.htPrimary)
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var daySettings: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                SchedulerFieldLabel(text: "Day")
                DatePicker("Day", selection: dayBinding, displayedComponents: .date)
                    .labelsHidden()
            }
            HStack(spacing: HTSpacing.md) {
                SchedulerTimePicker(label: "Start of day", time: $viewModel.form.dayStart)
                SchedulerTimePicker(label: "End of day", time: $viewModel.form.dayEnd)
            }
            SchedulerOptionPicker(label: "Buffer", options: GenerateDayForm.bufferOptions, selection: $viewModel.form.bufferMinutes) { "\($0) minutes" }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { SchedulerLogic.date(fromDateKey: viewModel.form.dateKey) ?? .now },
            set: { viewModel.form.dateKey = SchedulerLogic.dateKey($0) }
        )
    }

    private func taskCard(_ task: Binding<GenerateDayTaskDraft>) -> some View {
        let index = viewModel.form.tasks.firstIndex { $0.id == task.wrappedValue.id } ?? 0
        return VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack {
                Text("Task \(index + 1)")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                Spacer()
                if viewModel.form.tasks.count > 1 {
                    Button("Remove") { viewModel.removeTask(id: task.wrappedValue.id) }
                        .font(.htCaptionStrong)
                        .foregroundStyle(HTColor.danger700)
                }
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                SchedulerFieldLabel(text: "Title")
                TextField("e.g. Finish project outline", text: task.title)
                    .htField()
                    .onChange(of: task.wrappedValue.title) { _, value in
                        if value.count > GenerateDayTaskDraft.titleLimit {
                            task.wrappedValue.title = String(value.prefix(GenerateDayTaskDraft.titleLimit))
                        }
                    }
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                SchedulerFieldLabel(text: "Category")
                Picker("Category", selection: task.category) {
                    Text("Choose category").tag(String?.none)
                    ForEach(TaskCategory.allCases) { category in
                        Text(category.rawValue).tag(Optional(category.rawValue))
                    }
                }
                .pickerStyle(.menu)
                .tint(HTColor.textPrimary)
            }

            HStack(spacing: HTSpacing.md) {
                SchedulerOptionPicker(label: "Duration", options: GenerateDayTaskDraft.durationOptions, selection: task.durationMinutes) { "\($0) min" }
                SchedulerOptionPicker(label: "Importance", options: GenerateDayTaskDraft.levelOptions, selection: task.importance) { "\($0)/5" }
            }

            DisclosureGroup {
                optionalDetails(task)
            } label: {
                Text("Optional scheduling details")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textStrong)
            }
            .tint(HTColor.textStrong)
            .padding(HTSpacing.md)
            .background(HTColor.surfaceMuted)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func optionalDetails(_ task: Binding<GenerateDayTaskDraft>) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(spacing: HTSpacing.sm) {
                SchedulerOptionPicker(label: "Difficulty", options: GenerateDayTaskDraft.levelOptions, selection: task.difficulty) { "\($0)/5" }
                SchedulerOptionPicker(label: "Energy needed", options: GenerateDayTaskDraft.levelOptions, selection: task.requiredEnergy) { "\($0)/5" }
                SchedulerOptionPicker(label: "Focus needed", options: GenerateDayTaskDraft.levelOptions, selection: task.requiredFocus) { "\($0)/5" }
            }

            Toggle("Deadline on this day", isOn: Binding(
                get: { task.wrappedValue.deadlineMinutes != nil },
                set: { enabled in
                    task.wrappedValue.deadlineMinutes = enabled ? PlanningPreferences.minutes(from: viewModel.form.dayEnd) : nil
                }
            ))
            .font(.htBodyStrong)
            .foregroundStyle(HTColor.textStrong)
            if task.wrappedValue.deadlineMinutes != nil {
                SchedulerMinutePicker(label: "Deadline", minutes: Binding(
                    get: { task.wrappedValue.deadlineMinutes ?? 0 },
                    set: { task.wrappedValue.deadlineMinutes = $0 }
                ))
            }

            Toggle("Fixed-time event", isOn: task.isFixedTime)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textStrong)
                .onChange(of: task.wrappedValue.isFixedTime) { _, enabled in
                    if enabled, task.wrappedValue.fixedStartMinutes == nil {
                        task.wrappedValue.fixedStartMinutes = PlanningPreferences.minutes(from: viewModel.form.dayStart)
                    }
                }
            if task.wrappedValue.isFixedTime {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text("Fixed start")
                        .font(.htCaptionStrong)
                        .foregroundStyle(HTColor.textStrong)
                    SchedulerMinutePicker(label: "Fixed start", minutes: Binding(
                        get: { task.wrappedValue.fixedStartMinutes ?? PlanningPreferences.minutes(from: viewModel.form.dayStart) },
                        set: { task.wrappedValue.fixedStartMinutes = $0 }
                    ))
                }
            }
        }
        .padding(.top, HTSpacing.sm)
    }

    // MARK: - Draft

    private func draftContent(_ result: GeneratedDaySchedule) -> some View {
        let schedule = result.schedule
        return VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: HTSpacing.sm) {
                    Text("Your generated day")
                        .htPageTitle()
                    SchedulerBadge(
                        text: result.isDraft ? "Draft" : "Confirmed",
                        foreground: result.isDraft ? SchedulerPalette.amber800 : SchedulerPalette.emerald800,
                        background: result.isDraft ? HTColor.warning100 : HTColor.success100
                    )
                }
                Text("\(Self.dayText(schedule.selectedDate)) · \(result.bufferMinutes)-minute buffers")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
                Button("Start a new draft") { viewModel.startNewDraft() }
                    .buttonStyle(.htSecondary)
            }

            if let error = viewModel.errorMessage {
                AuthNotice(text: error, tone: .error)
            }
            ForEach(schedule.warnings, id: \.self) { warning in
                AuthNotice(text: warning, tone: .warning)
            }

            timeline(result)

            if !schedule.unscheduledTasks.isEmpty {
                unscheduledCard(schedule.unscheduledTasks)
            }

            confirmPanel(result)
        }
    }

    private func timeline(_ result: GeneratedDaySchedule) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HTEyebrowLabel(text: "Timeline", color: HTColor.textTertiary)
                Text("Optimized schedule")
                    .htSectionTitle()
                Text("Times are estimated, not guaranteed.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }

            if result.schedule.scheduledTasks.isEmpty {
                Text("No tasks could be placed in this day.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            } else {
                ForEach(result.schedule.scheduledTasks, id: \.taskId) { task in
                    scheduledRow(task, in: result)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func scheduledRow(_ task: DailyScheduledTask, in result: GeneratedDaySchedule) -> some View {
        let isFixed = result.meta.isFixedTime(task.taskId)
        let importance = result.meta.importance(for: task.taskId)
        return HStack(alignment: .top, spacing: HTSpacing.md) {
            Text(Self.clockText(task.scheduledStart))
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textStrong)
                .frame(width: 72, alignment: .trailing)
                .padding(.top, HTSpacing.md)

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                HStack(alignment: .top, spacing: HTSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textPrimary)
                        Text([
                            "\(task.estimatedDurationMinutes) min",
                            task.category,
                            importance.map { "importance \($0)/5" },
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }
                    Spacer(minLength: HTSpacing.sm)
                    SchedulerBadge(
                        text: "\(AIPredictResponse.percent(task.predictedSuccessProbability))% estimated",
                        foreground: HTColor.success700,
                        background: HTColor.success50
                    )
                }

                if let explanation = task.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textSecondary)
                }

                if result.isDraft && !isFixed {
                    HStack(spacing: HTSpacing.sm) {
                        Text("Adjust time")
                            .font(.htCaptionStrong)
                            .foregroundStyle(HTColor.textStrong)
                        SchedulerMinutePicker(
                            label: "Adjust \(task.title) time",
                            minutes: adjustBinding(for: task),
                            isEnabled: viewModel.savingTaskID != task.taskId
                        )
                    }
                }
                if isFixed {
                    HTEyebrowLabel(text: "Fixed-time event")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .htCard(padding: HTSpacing.md)
        }
    }

    /// Reads the drafted start; writing schedules a PATCH for that task.
    private func adjustBinding(for task: DailyScheduledTask) -> Binding<Int> {
        Binding(
            get: { SchedulerLogic.localMinutes(isoTimestamp: task.scheduledStart) ?? 0 },
            set: { minutes in
                Task { await viewModel.moveTask(taskID: task.taskId, toMinutes: minutes) }
            }
        )
    }

    private func unscheduledCard(_ tasks: [DailyUnscheduledTask]) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Couldn't schedule")
                .font(.htBodyStrong)
                .foregroundStyle(SchedulerPalette.amber950)
            ForEach(tasks, id: \.taskId) { task in
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.htBodyStrong)
                        .foregroundStyle(SchedulerPalette.amber950)
                    Text(task.reason)
                        .font(.htCaption)
                        .foregroundStyle(SchedulerPalette.amber800)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HTSpacing.lg)
        .background(HTColor.warning50)
        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(HTColor.warning100, lineWidth: 1)
        }
    }

    private func confirmPanel(_ result: GeneratedDaySchedule) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            if result.isDraft {
                Text("Ready to use this plan?")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                Text("Confirming creates only the scheduled tasks. Unscheduled tasks stay in this draft.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textSecondary)
                Button(viewModel.isBusy ? "Confirming…" : "Confirm daily plan") {
                    Task { await viewModel.confirm() }
                }
                .buttonStyle(HTPrimaryButtonStyle(fullWidth: true))
                .disabled(!viewModel.canConfirm)
                .padding(.top, HTSpacing.xs)
            } else {
                Text("Plan confirmed")
                    .font(.htBodyStrong)
                    .foregroundStyle(SchedulerPalette.emerald800)
                Text("Your tasks are now part of the active schedule.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    // MARK: - Formatting

    /// "Monday, November 9" for a `"yyyy-MM-dd"` key.
    private static func dayText(_ dateKey: String) -> String {
        guard let date = SchedulerLogic.date(fromDateKey: dateKey) else { return dateKey }
        return TaskTimeFormatting.headerDate(date)
    }

    private static func clockText(_ isoTimestamp: String) -> String {
        guard let date = TaskTimeFormatting.date(fromISO8601: isoTimestamp) else { return isoTimestamp }
        return TaskTimeFormatting.displayTime(date)
    }
}
