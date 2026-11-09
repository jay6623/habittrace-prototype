import SwiftUI

/// Result of handing an `OutcomeInput` to the owner of the sheet.
enum OutcomeSheetResult: Equatable {
    case success
    case failure(String)
}

/// Native equivalent of the PWA's outcome sheet at main: pick Completed or
/// Not completed, fill in optional details, then Submit. Validation reuses
/// `OutcomeRequestBuilder` through `OutcomeDraft`; the owner performs the
/// submission and reports back, and the sheet closes only on success.
struct OutcomeSheet: View {
    let task: HabitTraceTask
    let activeExecution: HabitTraceExecution?
    let onSubmit: (OutcomeInput) async -> OutcomeSheetResult

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OutcomeDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var minutesFieldFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: HTSpacing.md),
        GridItem(.flexible(), spacing: HTSpacing.md),
    ]

    init(
        task: HabitTraceTask,
        activeExecution: HabitTraceExecution?,
        now: Date = .now,
        onSubmit: @escaping (OutcomeInput) async -> OutcomeSheetResult
    ) {
        self.task = task
        self.activeExecution = activeExecution
        self.onSubmit = onSubmit
        _draft = State(initialValue: OutcomeDraft(activeStart: activeExecution?.actualStartDate, now: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    Text(subtitle)
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)

                    choiceGrid

                    switch draft.choice {
                    case .completed: completedFields
                    case .notCompleted: notCompletedFields
                    case nil: EmptyView()
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.htCaptionStrong)
                            .foregroundStyle(HTColor.danger700)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .htCard(background: HTColor.danger50)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(isSaving ? "Saving…" : "Submit")
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(!draft.canSubmit || isSaving)
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(HTColor.surfaceMuted)
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        minutesFieldFocused = false
                    }
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    savingOverlay
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var subtitle: String {
        var text = "Scheduled \(task.scheduledRangeText ?? "—")"
        if let start = activeExecution?.actualStartDate {
            text += " · started \(TaskTimeFormatting.displayTime(start))"
        }
        return text
    }

    private var choiceGrid: some View {
        LazyVGrid(columns: columns, spacing: HTSpacing.md) {
            OutcomeOptionButton(
                title: "Completed",
                detail: "I finished this plan",
                tint: HTColor.success50,
                border: HTColor.success100,
                isSelected: draft.choice == .completed
            ) {
                errorMessage = nil
                draft.choice = .completed
            }

            OutcomeOptionButton(
                title: "Not completed",
                detail: "I didn’t finish this plan",
                tint: HTColor.surfaceSecondary,
                border: HTColor.border,
                isSelected: draft.choice == .notCompleted
            ) {
                errorMessage = nil
                draft.choice = .notCompleted
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outcome")
    }

    private var completedFields: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Toggle(isOn: $draft.recordsFinishTime) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What time did you actually finish?")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    Text("(optional)")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
            }
            .onChange(of: draft.recordsFinishTime) { _, _ in errorMessage = nil }

            if draft.recordsFinishTime {
                DatePicker(
                    "Finished",
                    selection: $draft.finishedAt,
                    in: ...Date.now.addingTimeInterval(OutcomeRequestBuilder.futureTolerance),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.htBody)
                .onChange(of: draft.finishedAt) { _, _ in errorMessage = nil }
            }

            Text(finishHelpText)
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
        }
        .htCard()
    }

    private var finishHelpText: String {
        if let end = task.scheduledEndText {
            return "Leave blank to show the scheduled end (\(end)). It won’t be saved as your actual finish time."
        }
        return "Leave blank if you don’t know."
    }

    private var notCompletedFields: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            if !draft.isActive {
                Toggle("I didn’t start this task", isOn: Binding(
                    get: { draft.didNotStart },
                    set: { draft.setDidNotStart($0); errorMessage = nil }
                ))
                .font(.htBodyStrong)
            }

            if !draft.didNotStart {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: HTSpacing.xs) {
                        Text("How many minutes did you spend on this task?")
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textPrimary)
                        Text("(optional)")
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }

                    HStack {
                        TextField("Minutes", text: Binding(
                            get: { draft.minutesSpentText },
                            set: { draft.setMinutesSpentText($0); errorMessage = nil }
                        ))
                        .keyboardType(.numberPad)
                        .focused($minutesFieldFocused)
                        .font(.htBody)
                        .accessibilityLabel("Minutes spent")

                        Text("min")
                            .foregroundStyle(HTColor.textMuted)
                    }

                    Text("Leave blank if you’re not sure; it stays unrecorded.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: HTSpacing.xs) {
                    Text("What got in the way?")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    Text("(optional)")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }

                Picker("What got in the way?", selection: $draft.reason) {
                    Text("Prefer not to say").tag(FailureReason?.none)
                    ForEach(FailureReason.allCases) { reason in
                        Text(reason.label).tag(FailureReason?.some(reason))
                    }
                }
                .pickerStyle(.menu)
                .tint(HTColor.textPrimary)
                .onChange(of: draft.reason) { _, _ in errorMessage = nil }
            }
        }
        .htCard()
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: HTSpacing.sm) {
                ProgressView()
                Text("Saving outcome…")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
            }
            .padding(HTSpacing.xl)
            .htCard()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving outcome")
    }

    // MARK: - Submission

    private func submit() {
        Task {
            await performSubmit()
        }
    }

    private func performSubmit() async {
        guard !isSaving else { return }
        errorMessage = nil
        minutesFieldFocused = false

        if let message = draft.validationError() {
            errorMessage = message
            return
        }

        isSaving = true
        let outcome = await onSubmit(draft.input)
        isSaving = false

        switch outcome {
        case .success:
            dismiss()
        case .failure(let message):
            errorMessage = message
        }
    }
}

// MARK: - Option button

private struct OutcomeOptionButton: View {
    let title: String
    let detail: String
    let tint: Color
    let border: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                HStack {
                    Text(title)
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? HTColor.brand : HTColor.borderStrong)
                }

                Text(detail)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(HTSpacing.md)
            .background(tint)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? HTColor.brand : border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview("Not started yet") {
    OutcomeSheet(task: HabitTraceTask.previewTasks[0], activeExecution: nil) { _ in .success }
}

#Preview("Running") {
    let task = HabitTraceTask.previewTasks[1]
    let running = HabitTraceExecution(
        id: "ex", taskId: task.id, userId: "u",
        actualStartTime: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-900)),
        actualEndTime: nil, interruptionCount: nil, stoppedEarly: false,
        taskStatus: nil, failureReason: nil, createdAt: "c"
    )
    OutcomeSheet(task: task, activeExecution: running) { _ in .failure("Couldn’t save this outcome. Please try again.") }
}
#endif
