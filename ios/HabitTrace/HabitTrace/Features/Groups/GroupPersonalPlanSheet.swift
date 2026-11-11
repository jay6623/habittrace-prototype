import SwiftUI

/// The member's private schedule for a shared task, before it is sent as
/// a `GroupPersonalPlanRequest`. Pure value type so the request shape and
/// candidate handling can be tested without a view.
nonisolated struct GroupPersonalPlanDraft: Equatable, Sendable {
    static let durationRange = 1...720
    static let levelRange = 1...5

    /// Start of the work day in the planning time zone.
    var workDate: Date
    /// Minutes since midnight in the planning time zone.
    var startMinutes: Int
    var durationMinutes: Int
    var requiredEnergy = 3
    var requiredFocus = 3
    var currentEnergy = 3
    var currentFocus = 3

    /// Defaults: the next 15-minute slot after `now` and the task's
    /// estimate (or 30 minutes).
    static func initial(for task: GroupTask, now: Date = .now, timeZone: TimeZone = .current) -> GroupPersonalPlanDraft {
        let calendar = Self.calendar(in: timeZone)
        let slot = nextQuarterHour(after: now, calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute], from: slot)
        let estimate = task.estimatedDurationMinutes ?? 30
        return GroupPersonalPlanDraft(
            workDate: calendar.startOfDay(for: slot),
            startMinutes: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            durationMinutes: durationRange.contains(estimate) ? estimate : 30
        )
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func nextQuarterHour(after date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = components.minute ?? 0
        let rounded = Int((Double(minute) / 15).rounded(.up)) * 15
        let base = calendar.date(bySettingHour: components.hour ?? 0, minute: 0, second: 0, of: date) ?? date
        return calendar.date(byAdding: .minute, value: rounded, to: base) ?? date
    }

    /// The planned start as a `Date` in `timeZone`.
    func plannedStart(timeZone: TimeZone) -> Date? {
        Self.calendar(in: timeZone).date(
            bySettingHour: startMinutes / 60,
            minute: startMinutes % 60,
            second: 0,
            of: workDate
        )
    }

    var isDurationValid: Bool { Self.durationRange.contains(durationMinutes) }

    /// The request body, or nil when the duration is out of range.
    func request(timeZone: TimeZone) -> GroupPersonalPlanRequest? {
        guard isDurationValid, let start = plannedStart(timeZone: timeZone) else { return nil }
        return GroupPersonalPlanRequest(
            plannedStart: Self.isoString(for: start, timeZone: timeZone),
            plannedDurationMinutes: durationMinutes,
            timezoneName: timeZone.identifier,
            requiredEnergy: requiredEnergy,
            requiredFocus: requiredFocus,
            currentEnergy: currentEnergy,
            currentFocus: currentFocus
        )
    }

    /// Moves the draft to a candidate's start. Returns false when the
    /// candidate cannot be parsed.
    @discardableResult
    mutating func apply(candidateStart: String, timeZone: TimeZone) -> Bool {
        guard let date = GroupHelpers.date(fromTimestamp: candidateStart) else { return false }
        let calendar = Self.calendar(in: timeZone)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        workDate = calendar.startOfDay(for: date)
        startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return true
    }

    /// "2026-11-10T09:15:00+08:00": ISO-8601 with the zone's offset.
    static func isoString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    /// "2:00 PM" in `timeZone`.
    static func timeLabel(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "1 — Low", "2 — Moderate" … "5 — High".
    static func levelLabel(_ level: Int) -> String {
        switch level {
        case 1: "1 — Low"
        case 5: "5 — High"
        default: "\(level) — Moderate"
        }
    }

    /// Whole-number percentage for a 0–1 probability.
    static func percent(_ probability: Double) -> Int {
        Int((probability * 100).rounded())
    }
}

/// "My group task plan": the assignee's private prediction and schedule
/// for a shared task, with alternative times and conflict checks.
struct GroupPersonalPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: GroupTask
    let timeZone: TimeZone
    let preview: (GroupPersonalPlanRequest) async throws -> GroupPersonalPreview
    let confirm: (GroupPersonalPlanRequest) async throws -> HabitTraceTask

    private enum DoneState {
        case added
        case alreadyExists
    }

    @State private var draft: GroupPersonalPlanDraft
    @State private var durationText: String
    @State private var previewResult: GroupPersonalPreview?
    @State private var isChecking = false
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var done: DoneState?

    private let now = Date.now

    init(
        task: GroupTask,
        timeZone: TimeZone,
        preview: @escaping (GroupPersonalPlanRequest) async throws -> GroupPersonalPreview,
        confirm: @escaping (GroupPersonalPlanRequest) async throws -> HabitTraceTask
    ) {
        self.task = task
        self.timeZone = timeZone
        self.preview = preview
        self.confirm = confirm
        let initial = GroupPersonalPlanDraft.initial(for: task, timeZone: timeZone)
        _draft = State(initialValue: initial)
        _durationText = State(initialValue: String(initial.durationMinutes))
    }

    private var calendar: Calendar { GroupPersonalPlanDraft.calendar(in: timeZone) }

    private var isBusy: Bool { isChecking || isAdding }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        Text(task.title)
                            .font(.htCardTitle)
                            .foregroundStyle(HTColor.textPrimary)
                        Text("Your prediction and personal schedule are visible only to you.")
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }

                    if let done {
                        doneCard(done)
                    } else {
                        form
                        if let errorMessage {
                            GroupInlineError(text: errorMessage)
                        }
                        Button(isChecking ? "Checking…" : "Check my prediction") {
                            Task { await check() }
                        }
                        .buttonStyle(.htPrimary(fullWidth: true))
                        .disabled(isBusy || !draft.isDurationValid)

                        if let previewResult {
                            previewCard(previewResult)
                        }

                        Text("Group completion is recorded separately. Your personal plan stays in your history if the group task is removed.")
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("My group task plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .environment(\.timeZone, timeZone)
            .onChange(of: draft) { _, _ in
                previewResult = nil
                errorMessage = nil
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: HTSpacing.lg) {
            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                GroupFieldLabel(text: "Work date")
                DatePicker("Work date", selection: workDateBinding, in: calendar.startOfDay(for: now)..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .disabled(isBusy)
            }

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                GroupFieldLabel(text: "Start time")
                DatePicker("Start time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .disabled(isBusy)
                Text("Times use \(timeZone.identifier). Finish your work before the group deadline.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                GroupFieldLabel(text: "Duration (minutes)")
                TextField("e.g. 30", text: $durationText)
                    .keyboardType(.numberPad)
                    .htField()
                    .disabled(isBusy)
                    .onChange(of: durationText) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(3))
                        if digits != value {
                            durationText = digits
                            return
                        }
                        draft.durationMinutes = Int(digits) ?? 0
                    }
                if !draft.isDurationValid {
                    Text("Enter a duration between 1 and 720 minutes.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.danger700)
                }
            }

            levelPicker("Task energy needed", selection: $draft.requiredEnergy)
            levelPicker("Task focus needed", selection: $draft.requiredFocus)
            levelPicker("My expected energy", selection: $draft.currentEnergy)
            levelPicker("My expected focus", selection: $draft.currentFocus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func levelPicker(_ label: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: label)
            Picker(label, selection: selection) {
                ForEach(GroupPersonalPlanDraft.levelRange, id: \.self) { level in
                    Text(GroupPersonalPlanDraft.levelLabel(level)).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(HTColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .htField()
            .disabled(isBusy)
        }
    }

    private var workDateBinding: Binding<Date> {
        Binding(
            get: { draft.workDate },
            set: { draft.workDate = calendar.startOfDay(for: $0) }
        )
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: { draft.plannedStart(timeZone: timeZone) ?? draft.workDate },
            set: { date in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                draft.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    // MARK: - Preview

    private func previewCard(_ result: GroupPersonalPreview) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            if let prediction = result.prediction {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text("\(GroupPersonalPlanDraft.percent(prediction.successProbability))% estimated success")
                        .font(.htSectionTitle)
                        .foregroundStyle(HTColor.textPrimary)
                    Text(personalizationText(prediction.personalization))
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }

                if let reason = prediction.predictedFailureReason, !reason.isEmpty {
                    Text("Possible risk: \(reason.replacingOccurrences(of: "_", with: " "))")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.warning700)
                }

                if !prediction.recommendedActions.isEmpty {
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        ForEach(prediction.recommendedActions) { action in
                            Text("\(action.title): \(action.detail)")
                                .font(.htCaption)
                                .foregroundStyle(HTColor.textSecondary)
                        }
                    }
                }
            }

            if !result.conflicts.isEmpty {
                AuthNotice(
                    text: "Overlaps: \(result.conflicts.joined(separator: ", ")). Choose another time.",
                    tone: .error
                )
            }

            ForEach(result.warnings, id: \.self) { warning in
                AuthNotice(text: warning, tone: .warning)
            }

            if !result.candidates.isEmpty {
                VStack(alignment: .leading, spacing: HTSpacing.sm) {
                    Text("Other available times on this day")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    ForEach(result.candidates, id: \.plannedStart) { candidate in
                        Button(candidateLabel(candidate)) {
                            guard draft.apply(candidateStart: candidate.plannedStart, timeZone: timeZone) else { return }
                            Task { await check() }
                        }
                        .buttonStyle(.htSecondary(fullWidth: true))
                        .disabled(isBusy)
                    }
                }
            }

            Button(isAdding ? "Adding…" : "Add to my plans") {
                Task { await add() }
            }
            .buttonStyle(.htPrimary(fullWidth: true))
            .disabled(isBusy || !result.conflicts.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func personalizationText(_ personalization: AIPersonalization?) -> String {
        let base = personalization?.applied == true
            ? "Adjusted using \(personalization?.sampleCount ?? 0) of your recorded outcomes."
            : "Shared model estimate; limited personal history."
        return base + " Experimental guidance; not a validated personal success probability."
    }

    private func candidateLabel(_ candidate: GroupPersonalCandidate) -> String {
        let time = GroupHelpers.date(fromTimestamp: candidate.plannedStart)
            .map { GroupPersonalPlanDraft.timeLabel(for: $0, timeZone: timeZone) } ?? candidate.plannedStart
        return "\(time) · \(GroupPersonalPlanDraft.percent(candidate.successProbability))% estimated"
    }

    private func doneCard(_ state: DoneState) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text(state == .added ? "Added to your plans." : "This task is already in your personal plans.")
                .font(.htCardTitle)
                .foregroundStyle(HTColor.success700)
            Text("Track your work in Plans. Log your shared completion separately in Groups.")
                .font(.htBody)
                .foregroundStyle(HTColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(background: HTColor.success50)
    }

    // MARK: - Actions

    private func check() async {
        guard let request = draft.request(timeZone: timeZone) else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let result = try await preview(request)
            previewResult = result
            if result.personalTask != nil {
                done = .alreadyExists
            }
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't check this plan. Please try again.")
        }
    }

    private func add() async {
        guard let request = draft.request(timeZone: timeZone) else { return }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }

        do {
            _ = try await confirm(request)
            done = .added
        } catch {
            errorMessage = GroupHelpers.describeAPIError(
                error,
                fallback: "We couldn't add this plan. Please review the time and retry."
            )
        }
    }
}
