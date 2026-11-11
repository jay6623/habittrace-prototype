import SwiftUI

/// "Add a shared task" sheet. Mirrors `components/group/group-task-form`:
/// title, assignees, category, priority, optional due date and time
/// (5-minute steps), and an optional estimate.
struct GroupTaskFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [GroupMember]
    let timeZone: TimeZone
    let memberName: (GroupMember) -> String
    /// Creates the task; throws so the sheet can show the mapped error.
    let onSubmit: (GroupTaskCreate) async throws -> Void

    static let categories = ["Study", "Work", "Chores", "Fitness/Health", "Errands/Admin", "Hobbies/Leisure", "Social", "Other"]
    static let estimateRange = 1...720
    static let dueTimeSlots = Array(stride(from: 0, to: 24 * 60, by: 5))

    @State private var title = ""
    @State private var assignedIDs: Set<String> = []
    @State private var category = "Work"
    @State private var priority: GroupTaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var hasDueTime = false
    @State private var dueTimeMinutes = GroupTaskFormSheet.nextDueSlot()
    @State private var estimateText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        HTEyebrowLabel(text: "GROUP TASK")
                        Text("Add a shared task")
                            .htPageTitle()
                    }

                    titleField
                    assigneeField
                    categoryField
                    priorityField
                    dueDateField
                    dueTimeField
                    estimateField

                    if let errorMessage {
                        GroupInlineError(text: errorMessage)
                    }

                    Button(isSaving ? "Saving…" : "Add task") {
                        Task { await submit() }
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(isSaving)
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Group task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .environment(\.timeZone, timeZone)
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: "What needs to be done?")
            TextField("e.g. Prepare presentation slides", text: $title)
                .textInputAutocapitalization(.sentences)
                .htField()
                .disabled(isSaving)
                .onChange(of: title) { _, value in
                    if value.count > GroupHelpers.taskTitleMaxLength {
                        title = String(value.prefix(GroupHelpers.taskTitleMaxLength))
                    }
                }
        }
    }

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: "Assign to")
            if members.isEmpty {
                Text("No members yet.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: HTSpacing.sm)], alignment: .leading, spacing: HTSpacing.sm) {
                    ForEach(members) { member in
                        let isSelected = assignedIDs.contains(member.userId)
                        Button {
                            if isSelected {
                                assignedIDs.remove(member.userId)
                            } else {
                                assignedIDs.insert(member.userId)
                            }
                        } label: {
                            HStack(spacing: HTSpacing.xs) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                Text(memberName(member))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.htChip(isSelected: isSelected))
                        .disabled(isSaving)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: "Category")
            Picker("Category", selection: $category) {
                ForEach(Self.categories, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .tint(HTColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .htField()
            .disabled(isSaving)
        }
    }

    private var priorityField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: "Priority")
            Picker("Priority", selection: $priority) {
                ForEach(GroupTaskPriority.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSaving)
        }
    }

    private var dueDateField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Toggle(isOn: $hasDueDate.animation()) {
                GroupFieldLabel(text: "Due date (optional)")
            }
            .tint(HTColor.brand)
            .disabled(isSaving)
            if hasDueDate {
                DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .disabled(isSaving)
            }
        }
    }

    private var dueTimeField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Toggle(isOn: $hasDueTime.animation()) {
                GroupFieldLabel(text: "Due time (optional)")
            }
            .tint(HTColor.brand)
            .disabled(isSaving)
            if hasDueTime {
                Picker("Due time", selection: $dueTimeMinutes) {
                    ForEach(Self.dueTimeSlots, id: \.self) { minutes in
                        Text(Self.timeLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipped()
                .disabled(isSaving)
            }
        }
    }

    private var estimateField: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            GroupFieldLabel(text: "Estimated duration in minutes (optional)")
            TextField("e.g. 60", text: $estimateText)
                .keyboardType(.numberPad)
                .htField()
                .disabled(isSaving)
                .onChange(of: estimateText) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(3))
                    if digits != value { estimateText = digits }
                }
            Text("Assignees can adjust this when planning their own work.")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
        }
    }

    // MARK: - Submit

    private func submit() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Enter a task title."
            return
        }
        if trimmed.count > GroupHelpers.taskTitleMaxLength {
            errorMessage = "Keep the title under \(GroupHelpers.taskTitleMaxLength) characters."
            return
        }
        if hasDueTime, !hasDueDate {
            errorMessage = "Pick a due date to go with the due time."
            return
        }

        var estimate: Int?
        if !estimateText.isEmpty {
            guard let value = Int(estimateText), Self.estimateRange.contains(value) else {
                errorMessage = "Enter an estimate between 1 and 720 minutes."
                return
            }
            estimate = value
        }

        let input = GroupTaskCreate(
            title: trimmed,
            category: category,
            priority: priority,
            dueDate: hasDueDate ? GroupHelpers.isoDate(from: dueDate, timeZone: timeZone) : nil,
            dueTime: hasDueTime ? String(format: "%02d:%02d", dueTimeMinutes / 60, dueTimeMinutes % 60) : nil,
            estimatedDurationMinutes: estimate,
            dueTimezoneName: timeZone.identifier,
            assignedToIds: members.map(\.userId).filter { assignedIDs.contains($0) }
        )

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await onSubmit(input)
            dismiss()
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't save the task. Try again.")
        }
    }

    // MARK: - Helpers

    /// "2:05 PM" for minutes since midnight.
    static func timeLabel(_ minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):" + String(format: "%02d", minute) + (hour < 12 ? " AM" : " PM")
    }

    /// The next 5-minute slot after now, in the device zone.
    static func nextDueSlot(now: Date = .now, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let rounded = Int((Double(minutes) / 5).rounded(.up)) * 5
        return rounded >= 24 * 60 ? 0 : rounded
    }
}
