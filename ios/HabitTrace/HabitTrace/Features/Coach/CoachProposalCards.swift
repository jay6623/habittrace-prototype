import SwiftUI

/// Editable confirmation card for a coach task proposal.
struct TaskConfirmCard: View {
    let proposal: CoachTaskProposal
    let isBusy: Bool
    let onConfirm: (_ candidateStart: String?, _ draft: CoachTaskDraft) async -> Void
    let onCancel: () async -> Void

    @State private var selectedStart: String?
    @State private var draft: CoachTaskDraft
    @State private var durationText: String

    init(
        proposal: CoachTaskProposal,
        isBusy: Bool,
        onConfirm: @escaping (_ candidateStart: String?, _ draft: CoachTaskDraft) async -> Void,
        onCancel: @escaping () async -> Void
    ) {
        self.proposal = proposal
        self.isBusy = isBusy
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedStart = State(initialValue: proposal.options.first?.start)
        _draft = State(initialValue: proposal.task)
        _durationText = State(initialValue: "\(proposal.task.plannedDurationMin)")
    }

    private var categories: [String] {
        var items = TaskCategory.allCases.map(\.rawValue)
        if !items.contains(draft.taskCategory) { items.insert(draft.taskCategory, at: 0) }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            if !proposal.options.isEmpty {
                HTEyebrowLabel(text: "Choose a recommended time")
                VStack(spacing: HTSpacing.sm) {
                    ForEach(Array(proposal.options.enumerated()), id: \.element.start) { index, option in
                        optionRow(option, isBest: index == 0)
                    }
                }
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                fieldLabel("Title")
                TextField("Title", text: $draft.title)
                    .htField()
            }

            HStack(spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    fieldLabel("Date")
                    DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    fieldLabel("Time")
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }

            HStack(spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    fieldLabel("Category")
                    Picker("Category", selection: $draft.taskCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(HTColor.textPrimary)
                }
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    fieldLabel("Duration (min)")
                    TextField("60", text: $durationText)
                        .keyboardType(.numberPad)
                        .htField()
                        .onChange(of: durationText) { _, value in
                            let digits = value.filter(\.isNumber)
                            if digits != value { durationText = digits }
                            draft.plannedDurationMin = Int(digits) ?? 60
                        }
                }
            }

            HStack(spacing: HTSpacing.sm) {
                Button(isBusy ? "Adding…" : "Confirm & Add") {
                    Task { await onConfirm(selectedStart, draft) }
                }
                .buttonStyle(.htPrimary(fullWidth: true))
                .disabled(isBusy || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Cancel") {
                    Task { await onCancel() }
                }
                .buttonStyle(.htSecondary)
                .disabled(isBusy)
            }
        }
        .padding(HTSpacing.md)
        .background(HTColor.surfaceMuted)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                .strokeBorder(HTColor.border, lineWidth: 1)
        }
    }

    private func optionRow(_ option: CoachTimeOption, isBest: Bool) -> some View {
        let selected = selectedStart == option.start
        return Button {
            select(option)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(isBest ? "Best fit · " : "")\(Self.timeRange(option))")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    Spacer()
                    Text("\(Int((option.score * 100).rounded()))% fit")
                        .font(.htCaptionStrong)
                        .foregroundStyle(HTColor.success700)
                }
                if let reason = option.reasons.first {
                    Text(reason)
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HTSpacing.md)
            .background(selected ? HTColor.surface : HTColor.surfaceMuted)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                    .strokeBorder(selected ? HTColor.brand : HTColor.border, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Picking a time option rewrites the date and 24-hour time, as the PWA does.
    private func select(_ option: CoachTimeOption) {
        selectedStart = option.start
        guard let date = TaskTimeFormatting.date(fromISO8601: option.start) else { return }
        draft.plannedDate = TaskTimeFormatting.isoDate(from: date)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        draft.plannedStartTime = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { draft.plannedDate.flatMap { TaskTimeFormatting.date(fromISODate: $0) } ?? .now },
            set: { draft.plannedDate = TaskTimeFormatting.isoDate(from: $0) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = Self.minutes(from: draft.plannedStartTime) ?? 9 * 60
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.plannedStartTime = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
            }
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.htCaption)
            .foregroundStyle(HTColor.textMuted)
    }

    /// Accepts "HH:mm", "H:mm AM", or "HH:mm:ss".
    nonisolated static func minutes(from time: String) -> Int? {
        let trimmed = time.trimmingCharacters(in: .whitespaces).uppercased()
        let meridiem = trimmed.hasSuffix("AM") ? "AM" : trimmed.hasSuffix("PM") ? "PM" : nil
        let clock = meridiem == nil ? trimmed : String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var hour = parts[0]
        if let meridiem {
            if meridiem == "PM", hour != 12 { hour += 12 }
            if meridiem == "AM", hour == 12 { hour = 0 }
        }
        guard (0..<24).contains(hour), (0..<60).contains(parts[1]) else { return nil }
        return hour * 60 + parts[1]
    }

    static func timeRange(_ option: CoachTimeOption) -> String {
        guard let start = TaskTimeFormatting.date(fromISO8601: option.start),
              let end = TaskTimeFormatting.date(fromISO8601: option.end) else {
            return "\(option.start)–\(option.end)"
        }
        return "\(TaskTimeFormatting.displayTime(start))–\(TaskTimeFormatting.displayTime(end))"
    }
}

/// Confirmation card for a whole-day schedule draft.
struct DailyScheduleConfirmCard: View {
    let schedule: DailySchedule
    let isBusy: Bool
    let onConfirm: () async -> Void
    let onCancel: () -> Void
    /// Opens the draft in the scheduler, like the PWA's "Review & adjust".
    var onReview: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HTEyebrowLabel(text: "Daily plan draft", color: HTColor.success700)
                    Text(dateText)
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                }
                Spacer()
                Text("Draft")
                    .font(.htCaptionStrong)
                    .foregroundStyle(HTColor.warning700)
                    .padding(.horizontal, HTSpacing.sm)
                    .padding(.vertical, 2)
                    .background(HTColor.surface)
                    .clipShape(Capsule())
            }

            VStack(spacing: HTSpacing.sm) {
                ForEach(schedule.scheduledTasks, id: \.taskId) { task in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.htBodyStrong)
                                .foregroundStyle(HTColor.textPrimary)
                            HTMetaText(startText(task.scheduledStart), "\(task.estimatedDurationMinutes) min", task.category)
                        }
                        Spacer()
                        Text("\(Int((task.predictedSuccessProbability * 100).rounded()))% estimated")
                            .font(.htCaptionStrong)
                            .foregroundStyle(HTColor.success700)
                    }
                    .padding(HTSpacing.md)
                    .background(HTColor.surface)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                }
            }

            if !schedule.unscheduledTasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn’t fit")
                        .font(.htCaptionStrong)
                    ForEach(schedule.unscheduledTasks, id: \.taskId) { task in
                        Text("\(task.title): \(task.reason)")
                            .font(.htCaption)
                    }
                }
                .foregroundStyle(Color(hex: 0x78350F))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HTSpacing.md)
                .background(HTColor.warning100)
                .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
            }

            Text("Times and success likelihoods are estimates. Review before adding them to your schedule.")
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            if let onReview {
                Button("Review & adjust") {
                    onReview()
                }
                .buttonStyle(.htSecondary)
                .disabled(isBusy)
            }

            Button(isBusy ? "Confirming…" : "Confirm all") {
                Task { await onConfirm() }
            }
            .buttonStyle(.htPrimary(fullWidth: true))
            .disabled(isBusy || schedule.scheduledTasks.isEmpty)

            Button("Not now") {
                onCancel()
            }
            .font(.htCaptionStrong)
            .foregroundStyle(HTColor.textMuted)
            .frame(maxWidth: .infinity)
            .disabled(isBusy)
        }
        .padding(HTSpacing.md)
        .background(HTColor.success50)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                .strokeBorder(HTColor.success100, lineWidth: 1)
        }
    }

    private var dateText: String {
        guard let date = TaskTimeFormatting.date(fromISODate: schedule.selectedDate) else { return schedule.selectedDate }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func startText(_ iso: String) -> String {
        TaskTimeFormatting.date(fromISO8601: iso).map(TaskTimeFormatting.displayTime) ?? iso
    }
}
