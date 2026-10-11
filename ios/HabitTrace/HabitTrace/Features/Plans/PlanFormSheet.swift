import SwiftUI

/// What the Plans screen wants the form to do. Drives sheet presentation.
struct PlanFormRequest: Identifiable {
    let draft: PlanDraft
    /// Set when editing; excluded from overlap detection.
    let editingTaskID: String?

    var id: String { editingTaskID ?? "new" }

    var isEditing: Bool { editingTaskID != nil }
}

/// Native equivalent of the PWA's Quick Add form, in create and edit modes.
///
/// Fields and validation live in `PlanDraft`. Saving goes through
/// `PlansViewModel`, which checks overlaps with a fresh fetch, then
/// creates or updates and reconciles the list.
struct PlanFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PlansViewModel
    let request: PlanFormRequest
    let onSaved: (HabitTraceTask) -> Void

    @State private var draft: PlanDraft
    @State private var usesCustomDuration: Bool
    @State private var customDurationText: String
    @State private var hasAttemptedSave = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var conflicts: [HabitTraceTask]?

    private let calendar = Calendar.current

    init(
        request: PlanFormRequest,
        viewModel: PlansViewModel,
        onSaved: @escaping (HabitTraceTask) -> Void
    ) {
        self.request = request
        self.viewModel = viewModel
        self.onSaved = onSaved
        _draft = State(initialValue: request.draft)

        let isPreset = PlanDraft.durationPresets.contains(request.draft.durationMinutes)
        _usesCustomDuration = State(initialValue: !isPreset)
        _customDurationText = State(initialValue: isPreset ? "" : String(request.draft.durationMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveErrorMessage {
                    Section {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.htCaption)
                            .foregroundStyle(HTColor.danger700)
                    }
                }

                planSection
                scheduleSection
                durationSection
                detailsSection

                if let message = visibleValidationMessage {
                    Section {
                        Text(message)
                            .font(.htCaption)
                            .foregroundStyle(HTColor.danger700)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(request.isEditing ? "Edit plan" : "New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await attemptSave()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save plan")
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert(
                "Plans overlap",
                isPresented: isPresentingConflicts,
                presenting: conflicts
            ) { _ in
                Button("Save anyway") {
                    Task {
                        await save()
                    }
                }
                Button("Cancel", role: .cancel) {
                    conflicts = nil
                }
            } message: { conflicts in
                Text(conflictMessage(for: conflicts))
            }
        }
    }

    // MARK: - Sections

    private var planSection: some View {
        Section {
            TextField("Plan name", text: $draft.title)
                .textInputAutocapitalization(.sentences)
                .onChange(of: draft.title) { _, value in
                    if value.count > PlanDraft.titleLimit {
                        draft.title = String(value.prefix(PlanDraft.titleLimit))
                    }
                }

            TextField("Note (optional)", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
                .onChange(of: draft.notes) { _, value in
                    if value.count > PlanDraft.notesLimit {
                        draft.notes = String(value.prefix(PlanDraft.notesLimit))
                    }
                }
        } header: {
            Text(request.isEditing ? "Plan" : "What would you like to do?")
        }
    }

    private var scheduleSection: some View {
        Section("When") {
            DatePicker("Date", selection: dateBinding, displayedComponents: .date)

            DatePicker("Start time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
        }
    }

    private var durationSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HTSpacing.sm) {
                    ForEach(PlanDraft.durationPresets, id: \.self) { minutes in
                        let isSelected = !usesCustomDuration && draft.durationMinutes == minutes
                        Button("\(minutes)m") {
                            selectPreset(minutes)
                        }
                        .buttonStyle(.htChip(isSelected: isSelected))
                        .accessibilityLabel("\(minutes) minutes")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }

                    Button("Custom") {
                        selectCustom()
                    }
                    .buttonStyle(.htChip(isSelected: usesCustomDuration))
                    .accessibilityAddTraits(usesCustomDuration ? [.isSelected] : [])
                }
                .padding(.vertical, HTSpacing.xs)
            }
            .scrollClipDisabled()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            if usesCustomDuration {
                HStack {
                    TextField("Minutes", text: $customDurationText)
                        .keyboardType(.numberPad)
                        .onChange(of: customDurationText) { _, value in
                            applyCustomDuration(value)
                        }

                    Text("min")
                        .foregroundStyle(HTColor.textMuted)
                }
            }
        } header: {
            Text("How long?")
        } footer: {
            Text("Between 5 and 480 minutes.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Category", selection: $draft.category) {
                ForEach(TaskCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            Picker("Priority", selection: $draft.importance) {
                ForEach(1...5, id: \.self) { level in
                    Text(priorityLabel(level)).tag(level)
                }
            }
        }
    }

    // MARK: - Bindings

    private var dateBinding: Binding<Date> {
        Binding(
            get: { draft.plannedDate },
            set: { draft.plannedDate = calendar.startOfDay(for: $0) }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                calendar.date(
                    bySettingHour: draft.startMinutes / 60,
                    minute: draft.startMinutes % 60,
                    second: 0,
                    of: draft.plannedDate
                ) ?? draft.plannedDate
            },
            set: { date in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                draft.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private var isPresentingConflicts: Binding<Bool> {
        Binding(
            get: { conflicts != nil },
            set: { if !$0 { conflicts = nil } }
        )
    }

    // MARK: - Duration helpers

    private func selectPreset(_ minutes: Int) {
        usesCustomDuration = false
        customDurationText = ""
        draft.durationMinutes = minutes
    }

    private func selectCustom() {
        usesCustomDuration = true
        customDurationText = String(draft.durationMinutes)
    }

    /// Digits only, at most three, matching the PWA input. An empty field
    /// invalidates the draft until a number is entered.
    private func applyCustomDuration(_ value: String) {
        let digits = String(value.filter(\.isNumber).prefix(3))
        if digits != value {
            customDurationText = digits
            return
        }
        draft.durationMinutes = Int(digits) ?? 0
    }

    private var customDurationMissing: Bool {
        usesCustomDuration && customDurationText.isEmpty
    }

    // MARK: - Validation

    private var validationMessage: String? {
        if customDurationMissing {
            return "Enter how many minutes this plan should take."
        }
        return draft.validationError
    }

    /// Duration and time problems show immediately because they come from
    /// direct input. An empty title is only flagged after a save attempt;
    /// before that, the disabled Save button is the signal.
    private var visibleValidationMessage: String? {
        guard let message = validationMessage else { return nil }
        if draft.trimmedTitle.isEmpty, !hasAttemptedSave {
            return nil
        }
        return message
    }

    private var canSave: Bool {
        validationMessage == nil && !isSaving && !viewModel.isBusy
    }

    private func priorityLabel(_ level: Int) -> String {
        switch level {
        case 1: "1 — Low"
        case 5: "5 — High"
        default: "\(level)"
        }
    }

    // MARK: - Saving

    /// Validates, checks overlaps with a fresh fetch, then saves or asks.
    private func attemptSave() async {
        hasAttemptedSave = true
        saveErrorMessage = nil
        guard canSave else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let found = try await viewModel.overlappingPlans(
                for: draft,
                excludingTaskID: request.editingTaskID
            )

            if found.isEmpty {
                await save()
            } else {
                conflicts = found
            }
        } catch {
            saveErrorMessage = "Your plan wasn't saved. Your changes are still here — please try again."
        }
    }

    /// Creates or updates without re-checking overlaps ("Save anyway" path).
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        conflicts = nil

        let saved: HabitTraceTask?
        if let taskID = request.editingTaskID {
            saved = await viewModel.updatePlan(taskID: taskID, with: draft)
        } else {
            saved = await viewModel.createPlan(from: draft)
        }

        if let saved {
            onSaved(saved)
            dismiss()
        } else {
            // Surface the failure inside the sheet instead of the screen toast.
            saveErrorMessage = viewModel.actionErrorMessage ?? "Couldn't save this plan. Please try again."
            viewModel.actionErrorMessage = nil
        }
    }

    private func conflictMessage(for conflicts: [HabitTraceTask]) -> String {
        let noun = conflicts.count == 1 ? "another plan" : "other plans"
        let lines = conflicts.map { task in
            let time = task.plannedStartTime.map { TaskTimeFormatting.displayTime($0) } ?? "—"
            let minutes = task.plannedDurationMin ?? 0
            return "• \(task.title) · \(time) · \(minutes) min"
        }
        return "This plan overlaps with \(noun) on your schedule. Save it anyway, or cancel to adjust the time.\n\n"
            + lines.joined(separator: "\n")
    }
}

#if DEBUG
#Preview("New plan") {
    PlanFormSheet(
        request: PlanFormRequest(draft: PlanDraft.new(on: .now), editingTaskID: nil),
        viewModel: PlansViewModel(taskService: TaskService(), accessTokenProvider: { "" }),
        onSaved: { _ in }
    )
}

#Preview("Edit plan") {
    let task = HabitTraceTask.previewTasks[0]
    PlanFormSheet(
        request: PlanFormRequest(draft: PlanDraft(task: task) ?? PlanDraft.new(on: .now), editingTaskID: task.id),
        viewModel: PlansViewModel(taskService: TaskService(), accessTokenProvider: { "" }),
        onSaved: { _ in }
    )
}
#endif
