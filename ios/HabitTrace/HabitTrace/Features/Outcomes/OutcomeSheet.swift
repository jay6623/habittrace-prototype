import SwiftUI

/// Result of handing an `OutcomeInput` to the owner of the sheet.
enum OutcomeSheetResult: Equatable {
    case success
    case failure(String)
}

/// Native equivalent of the PWA's outcome sheet.
///
/// Step one offers Completed, Partly completed, Not this time, and Still
/// working, plus "I didn't start this plan" for plans with no recorded
/// start. Partly completed and Not this time move to a reason step with
/// an explicit Save button. Completed and Still working submit on tap.
/// Validation reuses `OutcomeRequestBuilder` through `OutcomeDraft`; the
/// owner performs the submission and reports back, and the sheet closes
/// only on success, keeping the user's input otherwise.
struct OutcomeSheet: View {
    let task: HabitTraceTask
    let activeExecution: HabitTraceExecution?
    let onSubmit: (OutcomeInput) async -> OutcomeSheetResult

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OutcomeDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Text shown in the percent field. Kept separately from the draft so
    /// clamping can write back to the field even when the clamped value
    /// equals what the draft already holds.
    @State private var percentText = ""
    @FocusState private var percentFieldFocused: Bool

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
        _draft = State(initialValue: OutcomeDraft(task: task, activeExecution: activeExecution, now: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    Text(subtitle)
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)

                    interruptionsCard

                    if !draft.isActive {
                        timesCard
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.htCaptionStrong)
                            .foregroundStyle(HTColor.danger700)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .htCard(background: HTColor.danger50)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    switch draft.step {
                    case .choose:
                        choiceGrid
                        if draft.offersNotStarted {
                            Button("I didn't start this plan") {
                                submit(.notStarted)
                            }
                            .buttonStyle(.htSecondary(fullWidth: true))
                        }
                    case .reason(let choice):
                        reasonStep(choice)
                    }
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

                // The number pad has no return key; give it a way to close
                // so the Save button below the field is reachable.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        percentFieldFocused = false
                    }
                }
            }
            .onChange(of: percentText) { _, value in
                let clamped = String(value.filter(\.isNumber).prefix(2))
                if clamped != value {
                    percentText = clamped
                    return
                }
                draft.setCompletionPercentText(clamped)
            }
            .onChange(of: draft.step) { _, _ in
                percentText = draft.completionPercentText
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
        draft.isActive
            ? "Your start time is recorded. How did it go?"
            : "How did it go? You can record progress even when the plan changed."
    }

    private var interruptionsCard: some View {
        HStack(alignment: .center, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text("Times interrupted")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)

                Text("Each time you were pulled away.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }

            Spacer(minLength: HTSpacing.sm)

            Stepper(value: $draft.interruptionCount, in: OutcomeRequestBuilder.interruptionRange) {
                Text("\(draft.interruptionCount)")
                    .font(.htCardTitle)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel("Times interrupted")
            .accessibilityValue("\(draft.interruptionCount)")
        }
        .htCard()
    }

    private var timesCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text("Forgot to start the timer?")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)

                Text("Enter your actual times to record a past outcome. Choose “Still working” to start now.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }

            DatePicker(
                "Started",
                selection: $draft.actualStart,
                in: ...draft.actualEnd,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.htBody)

            DatePicker(
                "Finished",
                selection: $draft.actualEnd,
                in: ...Date.now.addingTimeInterval(OutcomeRequestBuilder.futureTolerance),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.htBody)
        }
        .htCard()
    }

    private var choiceGrid: some View {
        LazyVGrid(columns: columns, spacing: HTSpacing.md) {
            OutcomeOptionButton(
                title: "Completed",
                detail: "I finished my plan",
                tint: HTColor.success50,
                border: HTColor.success100
            ) {
                submit(.completed)
            }

            OutcomeOptionButton(
                title: "Partly completed",
                detail: "I made some progress",
                tint: HTColor.warning50,
                border: HTColor.warning100
            ) {
                errorMessage = nil
                draft.choose(.partial)
            }

            OutcomeOptionButton(
                title: "Not this time",
                detail: "I couldn’t finish",
                tint: HTColor.surfaceSecondary,
                border: HTColor.border
            ) {
                errorMessage = nil
                draft.choose(.abandoned)
            }

            OutcomeOptionButton(
                title: "Still working",
                detail: "Keep the plan active",
                tint: HTColor.info50,
                border: HTColor.info100
            ) {
                submit(.stillWorking)
            }
        }
    }

    private func reasonStep(_ choice: OutcomeDraft.ReasonChoice) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Button {
                errorMessage = nil
                draft.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.htSecondary)

            Text(choice.title)
                .htSectionTitle()

            if choice == .partial {
                VStack(alignment: .leading, spacing: HTSpacing.sm) {
                    Text("How much did you complete? (%)")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)

                    HStack {
                        TextField("Enter 1–99", text: $percentText)
                            .keyboardType(.numberPad)
                            .focused($percentFieldFocused)
                            .font(.htBody)
                            .accessibilityLabel("Percent completed")

                        Text("%")
                            .foregroundStyle(HTColor.textMuted)
                    }
                }
                .htCard()
            }

            Text("What got in the way?")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)

            LazyVGrid(columns: columns, spacing: HTSpacing.sm) {
                ForEach(FailureReason.allCases) { reason in
                    let isSelected = draft.selectedReason == reason
                    Button(reason.label) {
                        draft.selectedReason = reason
                        percentFieldFocused = false
                    }
                    .buttonStyle(OutcomeReasonButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            Button("Save outcome") {
                if let result = draft.reasonStepResult {
                    submit(result)
                }
            }
            .buttonStyle(.htPrimary(fullWidth: true))
            .disabled(!draft.canSaveReasonStep(taskID: task.id, activeExecution: activeExecution))
        }
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

    private func submit(_ result: OutcomeResult) {
        Task {
            await performSubmit(result)
        }
    }

    private func performSubmit(_ result: OutcomeResult) async {
        guard !isSaving else { return }
        errorMessage = nil
        percentFieldFocused = false

        if let message = draft.validationError(for: result, taskID: task.id, activeExecution: activeExecution) {
            errorMessage = message
            return
        }

        isSaving = true
        let outcome = await onSubmit(draft.input(for: result))
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
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text(title)
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)

                Text(detail)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(HTSpacing.md)
            .background(tint)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private struct OutcomeReasonButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.htCaptionStrong)
            .multilineTextAlignment(.leading)
            .foregroundStyle(isSelected ? .white : HTColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, HTSpacing.md)
            .padding(.vertical, HTSpacing.sm)
            .background(isSelected ? HTColor.brand : HTColor.surface)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? HTColor.brand : HTColor.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
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
        actualEndTime: nil, interruptionCount: 0, stoppedEarly: false,
        taskStatus: nil, failureReason: nil, createdAt: "c"
    )
    OutcomeSheet(task: task, activeExecution: running) { _ in .failure("Couldn't save this outcome. Please try again.") }
}
#endif
