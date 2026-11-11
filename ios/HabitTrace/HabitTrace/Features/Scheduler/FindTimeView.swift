import SwiftUI

/// "Find a time" entry. Resolves the shared services from the environment
/// and hands them to `FindTimeScreen`, which owns the view model.
struct FindTimeView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    let initialDate: Date
    let initialTaskID: String?

    init(initialDate: Date = .now, initialTaskID: String? = nil) {
        self.initialDate = initialDate
        self.initialTaskID = initialTaskID
    }

    var body: some View {
        FindTimeScreen(
            taskService: taskService,
            accessTokenProvider: authManager.validAccessToken,
            preferences: authManager.planningPreferences,
            savePreferences: { [authManager] preferences in
                try await authManager.saveProfile(displayName: authManager.displayName, preferences: preferences)
            },
            initialDate: initialDate,
            initialTaskID: initialTaskID
        )
    }
}

/// Mirrors `/dashboard/scheduler`: availability editor, the day's plans,
/// and a detail panel with conflict-free times, personalized time
/// recommendations, and AI guidance for the selected plan.
struct FindTimeScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel: FindTimeViewModel
    @State private var showingGenerate = false

    init(
        taskService: TaskService,
        accessTokenProvider: @escaping FindTimeViewModel.AccessTokenProvider,
        preferences: PlanningPreferences,
        savePreferences: @escaping FindTimeViewModel.PreferencesSaver,
        initialDate: Date,
        initialTaskID: String?
    ) {
        _viewModel = StateObject(
            wrappedValue: FindTimeViewModel(
                taskService: taskService,
                accessTokenProvider: accessTokenProvider,
                preferences: preferences,
                savePreferences: savePreferences,
                initialDate: initialDate,
                initialTaskID: initialTaskID
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HTSpacing.md) {
                header
                availabilityPanel
                scheduleContent
            }
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.top, HTSpacing.screenTop)
            .padding(.bottom, HTSpacing.screenBottom)
        }
        .background(HTColor.surfaceMuted)
        .htToast($viewModel.toast)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: authManager.planningPreferences) { _, latest in
            viewModel.refreshPreferences(latest)
        }
        .sheet(isPresented: $showingGenerate) {
            NavigationStack {
                GenerateDayView(initialDate: viewModel.selectedDate, onCancel: { showingGenerate = false })
                    .navigationTitle("Generate day")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingGenerate = false }
                        }
                    }
            }
            .onDisappear { Task { await viewModel.load() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text("Make room in your day")
                .htPageTitle()
            Text("Choose a plan to find a time with a 15-minute buffer.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
            HStack(spacing: HTSpacing.sm) {
                Button("Generate today's plan") { showingGenerate = true }
                    .buttonStyle(.htPrimary)
                Spacer(minLength: 0)
                DatePicker("Schedule date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Daily availability

    private var availabilityPanel: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Daily availability")
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)
            Text("Your current daily availability is set from **\(PlanningPreferences.displayTime(viewModel.preferences.workStart))** to **\(PlanningPreferences.displayTime(viewModel.preferences.workEnd))**. Suggested times only use this window.")
                .font(.htBody)
                .foregroundStyle(HTColor.textSecondary)

            HStack(spacing: HTSpacing.md) {
                SchedulerTimePicker(label: "From", time: $viewModel.draftWorkStart)
                SchedulerTimePicker(label: "Until", time: $viewModel.draftWorkEnd)
            }

            Button(viewModel.isSavingAvailability ? "Saving…" : "Save availability") {
                Task { await viewModel.saveAvailability() }
            }
            .buttonStyle(.htPrimary)
            .disabled(viewModel.isSavingAvailability)

            if let error = viewModel.availabilityError {
                Text(error)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.danger700)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    // MARK: - Schedule

    @ViewBuilder
    private var scheduleContent: some View {
        if viewModel.loadFailed {
            VStack(alignment: .leading, spacing: HTSpacing.md) {
                Text("Couldn't load your schedule.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textPrimary)
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.htSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .htCard()
        } else if viewModel.isLoading && viewModel.tasks.isEmpty {
            Text("Loading schedule…")
                .font(.htBody)
                .foregroundStyle(HTColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .htCard()
        } else {
            planList
            detailPanel
        }
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text(TaskTimeFormatting.headerDate(viewModel.selectedDate))
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)

            if viewModel.tasks.isEmpty {
                Text("No plans for this date. Add a plan from the Plans screen.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            } else {
                let overlapping = viewModel.overlappingIDs
                VStack(spacing: HTSpacing.sm) {
                    ForEach(viewModel.tasks) { task in
                        Button {
                            viewModel.selectTask(task.id)
                        } label: {
                            planRow(task, isSelected: task.id == viewModel.selectedTaskID, overlaps: overlapping.contains(task.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(task.id == viewModel.selectedTaskID ? .isSelected : [])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func planRow(_ task: HabitTraceTask, isSelected: Bool, overlaps: Bool) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(task.title)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
            Text("\(task.plannedStartTime.map(TaskTimeFormatting.displayTime) ?? "—") · \(task.plannedDurationMin ?? 0) min · \(Self.statusLabel(task.taskStatus))")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
            if overlaps {
                Text("Overlaps another plan")
                    .font(.htCaption)
                    .foregroundStyle(SchedulerPalette.amber800)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HTSpacing.md)
        .background(isSelected ? HTColor.surfaceMuted : HTColor.surface)
        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(isSelected ? HTColor.brand : HTColor.border, lineWidth: 1)
        }
    }

    private static func statusLabel(_ status: String?) -> String {
        switch status {
        case "pending": "Planned"
        case "success": "Completed"
        default: "Not completed"
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPanel: some View {
        if let task = viewModel.selectedTask {
            VStack(alignment: .leading, spacing: HTSpacing.md) {
                VStack(alignment: .leading, spacing: HTSpacing.sm) {
                    Text(task.title)
                        .htSectionTitle()
                    if let percent = viewModel.successPercent {
                        SchedulerBadge(text: "Estimated success \(percent)%", foreground: HTColor.success700, background: HTColor.success50)
                    }
                }

                if let personalization = viewModel.prediction?.personalization, personalization.applied {
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        Text("Personalized using \(personalization.sampleCount) previous plans")
                            .font(.htCaptionStrong)
                            .foregroundStyle(SchedulerPalette.emerald900)
                        if let factor = personalization.factors.first, !factor.message.isEmpty {
                            Text(factor.message)
                                .font(.htCaption)
                                .foregroundStyle(SchedulerPalette.emerald800)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HTSpacing.sm)
                    .background(HTColor.success50)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                }

                Text("\(task.plannedDurationMin ?? 0) minutes · suggestions use your daily availability (\(PlanningPreferences.displayTime(viewModel.preferences.workStart))–\(PlanningPreferences.displayTime(viewModel.preferences.workEnd))).")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)

                if task.taskStatus != "pending" {
                    Text("This plan already has an outcome. Create a new plan to try it again.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textPrimary)
                } else {
                    slotsSection
                    recommendationCard(task)
                }

                Divider()
                guidanceSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .htCard()
        } else {
            Text("Select a plan to see available times.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .htCard()
        }
    }

    // MARK: Conflict-free times

    private var slotsSection: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            HStack(alignment: .top, spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HTEyebrowLabel(text: "Scheduling rules", color: HTColor.textTertiary)
                    Text("Conflict-free times")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                }
                Spacer(minLength: HTSpacing.sm)
                SchedulerBadge(text: "15 min buffer")
            }

            let slots = viewModel.slots
            if slots.isEmpty {
                Text("No buffered slot fits. Try a shorter plan, another date, or a wider daily availability window.")
                    .font(.htCaption)
                    .foregroundStyle(SchedulerPalette.amber800)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: HTSpacing.sm)], spacing: HTSpacing.sm) {
                    ForEach(slots, id: \.self) { minutes in
                        Button(TaskTimeFormatting.displayTime(SchedulerLogic.storedTime(minutes: minutes))) {
                            Task { await viewModel.move(toMinutes: minutes) }
                        }
                        .buttonStyle(.htSecondary)
                        .disabled(viewModel.isSaving)
                    }
                }
            }

            Text("These options only check daily availability and schedule conflicts. Selecting one saves the change immediately.")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
        }
    }

    // MARK: Personalized time recommendations

    private func recommendationCard(_ task: HabitTraceTask) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            HTEyebrowLabel(text: "Personalized recommendation · Experimental", color: SchedulerPalette.violet700)
            Text("Which free time fits this plan best?")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
            Text("We compare conflict-free times using plan length, time of day, workload, category, energy, and focus.")
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            Button(viewModel.isRecommending ? "Finding times…" : "Get personalized recommendations") {
                Task { await viewModel.rankTimes() }
            }
            .buttonStyle(.htPrimary)
            .tint(SchedulerPalette.violet700)
            .disabled(!viewModel.canRequestRecommendations)

            if task.aiPlanInputId == nil {
                Text(viewModel.predictionFailed
                     ? "We couldn't prepare recommendations for this plan. Check the backend connection and try again."
                     : "Preparing personalized recommendations for this plan…")
                    .font(.htCaptionStrong)
                    .foregroundStyle(SchedulerPalette.amber800)
            }

            if let error = viewModel.recommendationError {
                Text(error)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.danger700)
            }

            if !viewModel.topCandidates.isEmpty {
                VStack(spacing: HTSpacing.sm) {
                    ForEach(viewModel.topCandidates) { candidate in
                        Button {
                            Task { await viewModel.accept(candidate) }
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSaving)
                    }
                }
            }

            Text("Estimates are guidance and may change as your plan changes.")
                .font(.caption2)
                .foregroundStyle(SchedulerPalette.violet800.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HTSpacing.lg)
        .background(SchedulerPalette.violet50)
        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(SchedulerPalette.violet200, lineWidth: 1)
        }
    }

    private func candidateRow(_ candidate: TimeCandidate) -> some View {
        HStack(alignment: .top, spacing: HTSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Self.clockText(candidate.candidateStart))–\(Self.clockText(candidate.candidateEnd))")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.ink)
                Text("Conflict-free · personalized fit")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
                if let personalization = candidate.reasonSnapshot?.personalization, personalization.applied {
                    Text("Based on \(personalization.sampleCount) previous plans")
                        .font(.caption2)
                        .foregroundStyle(SchedulerPalette.violet700)
                }
            }
            Spacer(minLength: HTSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text("#\(candidate.rank)")
                    .font(.htCaptionStrong)
                    .foregroundStyle(SchedulerPalette.violet700)
                Text("Estimated success \(candidate.successPercent)%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SchedulerPalette.violet600)
            }
        }
        .padding(HTSpacing.md)
        .background(HTColor.surface)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                .strokeBorder(SchedulerPalette.violet200, lineWidth: 1)
        }
    }

    private static func clockText(_ isoTimestamp: String) -> String {
        guard let date = TaskTimeFormatting.date(fromISO8601: isoTimestamp) else { return isoTimestamp }
        return TaskTimeFormatting.displayTime(date)
    }

    // MARK: Guidance

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            HTEyebrowLabel(text: "Personalized recommendation", color: HTColor.success700)
            Text("How to make this plan easier to complete")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)

            if viewModel.isPredicting {
                Text("Checking guidance…")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textPrimary)
            } else {
                Text(viewModel.prediction != nil
                     ? "Based on this plan's estimated success score, the suggestions below highlight practical changes that may make it easier to complete."
                     : "AI guidance is unavailable for this plan. You can still use the schedule checks above.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)

                ForEach(viewModel.prediction?.recommendedActions ?? []) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textPrimary)
                        Text(action.detail)
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HTSpacing.md)
                    .background(HTColor.surfaceMuted)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                }
            }
        }
    }
}
