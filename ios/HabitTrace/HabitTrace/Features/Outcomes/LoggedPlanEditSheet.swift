import SwiftUI

/// Native equivalent of the PWA's "Edit logged plan" form: adjusts the
/// plan's fields and revises its recorded outcome in two sequential calls.
struct LoggedPlanEditSheet: View {
    let task: HabitTraceTask
    @ObservedObject var viewModel: PlansViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var planDraft: PlanDraft
    @State private var usesCustomDuration: Bool
    @State private var customDurationText: String

    @State private var execution: HabitTraceExecution?
    @State private var isLoadingExecution = true
    @State private var loadErrorMessage: String?

    @State private var result: OutcomeStatus?
    @State private var recordsStart = false
    @State private var actualStart = Date()
    @State private var recordsEnd = false
    @State private var actualEnd = Date()
    @State private var minutesText = ""
    @State private var interruptionsText = ""
    @State private var progressText = ""
    @State private var reason: FailureReason?

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(task: HabitTraceTask, viewModel: PlansViewModel, onSaved: @escaping () -> Void) {
        self.task = task
        self.viewModel = viewModel
        self.onSaved = onSaved

        let draft = PlanDraft(task: task) ?? PlanDraft.new(on: .now)
        _planDraft = State(initialValue: draft)
        let isPreset = PlanDraft.durationPresets.contains(draft.durationMinutes)
        _usesCustomDuration = State(initialValue: !isPreset)
        _customDurationText = State(initialValue: isPreset ? "" : String(draft.durationMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.htCaption)
                            .foregroundStyle(HTColor.danger700)
                    }
                }

                planSection
                scheduleSection
                durationSection
                resultSection

                if let result, result != .notStarted {
                    executionSection(result)
                }

                if result != .completed {
                    reasonSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit logged plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save changes")
                        }
                    }
                    .disabled(isSaving || isLoadingExecution)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task {
                await loadExecution()
            }
        }
    }

    // MARK: - Sections

    private var planSection: some View {
        Section("Plan") {
            TextField("Plan name", text: $planDraft.title)
                .onChange(of: planDraft.title) { _, value in
                    if value.count > PlanDraft.titleLimit {
                        planDraft.title = String(value.prefix(PlanDraft.titleLimit))
                    }
                }

            TextField("Note (optional)", text: $planDraft.notes, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: planDraft.notes) { _, value in
                    if value.count > PlanDraft.notesLimit {
                        planDraft.notes = String(value.prefix(PlanDraft.notesLimit))
                    }
                }
        }
    }

    private var scheduleSection: some View {
        Section("When") {
            DatePicker("Date", selection: Binding(
                get: { planDraft.plannedDate },
                set: { planDraft.plannedDate = Calendar.current.startOfDay(for: $0) }
            ), displayedComponents: .date)

            DatePicker("Start time", selection: Binding(
                get: {
                    Calendar.current.date(
                        bySettingHour: planDraft.startMinutes / 60,
                        minute: planDraft.startMinutes % 60,
                        second: 0,
                        of: planDraft.plannedDate
                    ) ?? planDraft.plannedDate
                },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    planDraft.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
        }
    }

    private var durationSection: some View {
        Section {
            DurationChips(
                durationMinutes: $planDraft.durationMinutes,
                usesCustom: $usesCustomDuration,
                customText: $customDurationText
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } header: {
            Text("How long?")
        } footer: {
            Text("Between 5 and 480 minutes.")
        }
    }

    private var resultSection: some View {
        Section("Log result") {
            if isLoadingExecution {
                HStack {
                    ProgressView()
                    Text("Loading saved outcome…")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                }
            } else if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.danger700)
            }

            Picker("Result", selection: $result) {
                Text("Choose…").tag(OutcomeStatus?.none)
                Text("Completed · Finished as planned").tag(OutcomeStatus?.some(.completed))
                Text("Partly completed · Some progress").tag(OutcomeStatus?.some(.partial))
                Text("Not completed · Didn’t finish").tag(OutcomeStatus?.some(.abandoned))
                Text("Didn’t start · No execution time").tag(OutcomeStatus?.some(.notStarted))
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .onChange(of: result) { _, value in
                errorMessage = nil
                if value == .completed {
                    reason = nil
                }
            }
        }
    }

    private func executionSection(_ result: OutcomeStatus) -> some View {
        Section {
            Toggle("Started", isOn: $recordsStart)
            if recordsStart {
                DatePicker("Started at", selection: $actualStart, displayedComponents: [.date, .hourAndMinute])
            }

            Toggle("Finished", isOn: $recordsEnd)
            if recordsEnd {
                DatePicker("Finished at", selection: $actualEnd, displayedComponents: [.date, .hourAndMinute])
            }

            if result != .completed {
                LabeledContent("Minutes spent (optional)") {
                    TextField("—", text: digitsBinding($minutesText, maxLength: 4))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
            }

            LabeledContent("Times interrupted (optional)") {
                TextField("—", text: digitsBinding($interruptionsText, maxLength: 5))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }

            if result == .partial {
                LabeledContent("Completed (%)") {
                    TextField("1–99", text: digitsBinding($progressText, maxLength: 2))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
            }
        } header: {
            Text("Actual execution")
        } footer: {
            Text("Optional. Leave a time blank if you don’t know it; it stays unrecorded.")
        }
    }

    private var reasonSection: some View {
        Section {
            Picker("What got in the way?", selection: $reason) {
                Text("Prefer not to say").tag(FailureReason?.none)
                ForEach(FailureReason.allCases) { reason in
                    Text(reason.label).tag(FailureReason?.some(reason))
                }
            }
        } footer: {
            Text("(optional)")
        }
    }

    private func digitsBinding(_ binding: Binding<String>, maxLength: Int) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                binding.wrappedValue = String(value.filter(\.isNumber).prefix(maxLength))
                errorMessage = nil
            }
        )
    }

    // MARK: - Loading and saving

    private func loadExecution() async {
        isLoadingExecution = true
        defer { isLoadingExecution = false }

        do {
            guard let latest = try await viewModel.latestFinishedExecution(for: task.id) else {
                loadErrorMessage = "No saved outcome was found for this plan."
                return
            }
            execution = latest
            seed(from: latest)
        } catch {
            loadErrorMessage = "Couldn’t load the saved outcome for this plan."
        }
    }

    private func seed(from latest: HabitTraceExecution) {
        if let outcome = latest.outcomeStatus {
            result = outcome
        } else if task.taskStatus == "success" {
            result = .completed
        }

        if let start = latest.actualStartDate {
            recordsStart = true
            actualStart = start
        }
        if let end = latest.actualEndDate {
            recordsEnd = true
            actualEnd = end
        }
        if let minutes = latest.activeMinutes {
            minutesText = String(minutes)
        }
        if let interruptions = latest.interruptionCount {
            interruptionsText = String(interruptions)
        }
        if let ratio = latest.completionRatio {
            progressText = String(Int((ratio * 100).rounded()))
        }
        reason = latest.failureReasonCode
    }

    private func save() async {
        errorMessage = nil

        if planDraft.trimmedTitle.isEmpty {
            errorMessage = "Give your plan a name."
            return
        }
        if DurationChips.customMissing(usesCustom: usesCustomDuration, customText: customDurationText) {
            errorMessage = "Enter how many minutes this plan should take."
            return
        }
        if !PlanDraft.durationRange.contains(planDraft.durationMinutes) {
            errorMessage = "Choose a duration between 5 and 480 minutes."
            return
        }
        guard let result else {
            errorMessage = "Choose the actual outcome. Older failed records do not include a completion percentage."
            return
        }
        guard let execution else {
            errorMessage = "No saved outcome was found for this plan."
            return
        }

        // A stored time can be corrected but not removed.
        if execution.actualStartDate != nil, !recordsStart, result != .notStarted {
            errorMessage = OutcomeValidationError.savedTimeRemoved("start").errorDescription
            return
        }
        if execution.actualEndDate != nil, !recordsEnd, result != .notStarted {
            errorMessage = OutcomeValidationError.savedTimeRemoved("finish").errorDescription
            return
        }

        let revision = RevisionInput(
            result: result,
            actualStart: recordsStart ? actualStart : nil,
            actualEnd: recordsEnd ? actualEnd : nil,
            interruptions: interruptionsText.isEmpty ? nil : Int(interruptionsText),
            progressPercent: progressText.isEmpty ? nil : Int(progressText),
            minutesSpent: minutesText.isEmpty ? nil : Int(minutesText),
            reason: reason
        )

        let request: ExecutionOutcomeRequest
        do {
            request = try OutcomeRequestBuilder.buildRevision(revision, existing: execution)
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
            return
        }

        isSaving = true
        defer { isSaving = false }

        let saved = await viewModel.updateLoggedPlan(
            taskID: task.id,
            draft: planDraft,
            executionID: execution.id,
            revision: request
        )

        if saved {
            onSaved()
            dismiss()
        } else {
            errorMessage = viewModel.actionErrorMessage ?? "Couldn’t save these changes. Please try again."
            viewModel.actionErrorMessage = nil
        }
    }
}
