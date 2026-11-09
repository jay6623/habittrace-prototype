import SwiftUI

/// Calendar tab: month grid or week list over every plan, with the PWA's
/// category and priority filters, a day sheet, read-only plan details,
/// and add-from-day. Data is the shared, unfiltered task array.
struct CalendarView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week = "Week"
        var id: String { rawValue }
    }

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    @State private var mode: Mode = .month
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)
    @State private var weekAnchor: Date = Calendar.current.startOfDay(for: .now)
    @State private var categoryFilter: TaskCategory?
    @State private var priorityFilter: Int?
    @State private var selectedDay: DayKey?
    @State private var detailTask: HabitTraceTask?
    @State private var planFormRequest: PlanFormRequest?
    @State private var loadErrorMessage: String?
    @State private var isLoading = false
    @State private var toast: HTToastMessage?

    private let calendar = Calendar.current

    struct DayKey: Identifiable, Hashable {
        let date: Date
        var id: Date { date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    header

                    if let loadErrorMessage {
                        PlansErrorView(message: loadErrorMessage) {
                            Task { await load() }
                        }
                    } else if isLoading && taskService.tasks.isEmpty {
                        PlansLoadingView()
                    } else {
                        switch mode {
                        case .month: monthGrid
                        case .week: weekList
                        }
                        legend
                    }
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
            .htToast($toast)
            .sheet(item: $selectedDay) { day in
                daySheet(for: day.date)
            }
            .sheet(item: $detailTask) { task in
                PlanDetailsSheet(task: task)
            }
            .sheet(item: $planFormRequest) { request in
                PlanFormSheet(
                    request: request,
                    actions: .creating(with: taskService, accessToken: authManager.validAccessToken)
                ) { task in
                    toast = .success("Plan added for \(task.plannedDate ?? "").")
                    Task { await load() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HTEyebrowLabel(text: "Calendar")
                    Text("Task Calendar")
                        .htPageTitle()
                }
                Spacer(minLength: HTSpacing.sm)
                Button {
                    presentAddPlan(on: .now)
                } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.htPrimary)
            }

            HStack(spacing: HTSpacing.xs) {
                stepButton(systemImage: "chevron.left", label: mode == .month ? "Previous month" : "Previous week") {
                    step(-1)
                }

                Text(rangeLabel)
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                stepButton(systemImage: "chevron.right", label: mode == .month ? "Next month" : "Next week") {
                    step(1)
                }

                Button("Today") {
                    displayedMonth = calendar.startOfMonth(for: .now)
                    weekAnchor = calendar.startOfDay(for: .now)
                }
                .buttonStyle(.htSecondary)
            }
            .htCard(padding: HTSpacing.xs)

            HStack {
                PlansFilterMenus(category: $categoryFilter, priority: $priorityFilter)
                Spacer()
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .onChange(of: mode) { _, newMode in
                    switch newMode {
                    case .week:
                        // Anchor the week on today's day-of-month inside the displayed month.
                        let todayDay = calendar.component(.day, from: .now)
                        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<29
                        let day = min(todayDay, range.count)
                        weekAnchor = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth) ?? displayedMonth
                    case .month:
                        displayedMonth = calendar.startOfMonth(for: weekAnchor)
                    }
                }
            }
        }
    }

    private var rangeLabel: String {
        switch mode {
        case .month:
            return displayedMonth.formatted(.dateTime.month(.wide).year())
        case .week:
            let start = weekStart(containing: weekAnchor)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
            let startText = sameYear
                ? start.formatted(.dateTime.month(.abbreviated).day())
                : start.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(startText) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(HTColor.textStrong)
                .frame(width: HTControlHeight.standard, height: HTControlHeight.standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func step(_ direction: Int) {
        switch mode {
        case .month:
            displayedMonth = calendar.date(byAdding: .month, value: direction, to: displayedMonth) ?? displayedMonth
        case .week:
            weekAnchor = calendar.date(byAdding: .day, value: 7 * direction, to: weekAnchor) ?? weekAnchor
        }
    }

    // MARK: - Month grid

    private var weekdaySymbols: [String] {
        calendar.veryShortStandaloneWeekdaySymbols.indices.map { calendar.shortStandaloneWeekdaySymbols[$0] }
    }

    private var monthCells: [Date?] {
        let firstWeekdayOffset = (calendar.component(.weekday, from: displayedMonth) - 1 + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: firstWeekdayOffset)
        for day in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: day, to: displayedMonth))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: HTSpacing.sm) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.htEyebrow)
                        .foregroundStyle(HTColor.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 72)
                    }
                }
            }
        }
        .htCard(padding: HTSpacing.sm)
    }

    private func dayCell(_ date: Date) -> some View {
        let plans = plans(on: date)
        let isToday = calendar.isDateInToday(date)
        return Button {
            selectedDay = DayKey(date: date)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.htCaptionStrong)
                    .foregroundStyle(isToday ? .white : HTColor.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? HTColor.ink : .clear)
                    .clipShape(Circle())

                ForEach(plans.prefix(2)) { task in
                    Text(task.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(chipPalette(for: task).foreground)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(chipPalette(for: task).background)
                        .clipShape(.rect(cornerRadius: 3))
                }

                if plans.count > 2 {
                    Text("+\(plans.count - 2) more")
                        .font(.system(size: 9))
                        .foregroundStyle(HTColor.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(HTColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.sm, style: .continuous)
                    .strokeBorder(isToday ? HTColor.ink : HTColor.border, lineWidth: isToday ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View plans on \(TaskTimeFormatting.mediumDate(date))")
        .accessibilityValue(plans.isEmpty ? "No plans" : "\(plans.count) plans")
    }

    // MARK: - Week list

    private var weekList: some View {
        let start = weekStart(containing: weekAnchor)
        return VStack(spacing: HTSpacing.md) {
            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                let plans = plans(on: date)
                Button {
                    selectedDay = DayKey(date: date)
                } label: {
                    VStack(alignment: .leading, spacing: HTSpacing.sm) {
                        HStack {
                            Text(date.formatted(.dateTime.weekday(.wide)))
                                .font(.htBodyStrong)
                                .foregroundStyle(HTColor.textPrimary)
                            Spacer()
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.htCaptionStrong)
                                .foregroundStyle(calendar.isDateInToday(date) ? .white : HTColor.textMuted)
                                .padding(.horizontal, HTSpacing.sm)
                                .padding(.vertical, 2)
                                .background(calendar.isDateInToday(date) ? HTColor.ink : .clear)
                                .clipShape(Capsule())
                        }

                        if plans.isEmpty {
                            Text("–")
                                .font(.htCaption)
                                .foregroundStyle(HTColor.textTertiary)
                        } else {
                            ForEach(plans) { task in
                                HStack(spacing: HTSpacing.sm) {
                                    Circle()
                                        .fill(chipPalette(for: task).foreground)
                                        .frame(width: 8, height: 8)
                                    Text(task.title)
                                        .font(.htCaptionStrong)
                                        .foregroundStyle(HTColor.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(task.scheduledRangeText ?? "")
                                        .font(.htCaption)
                                        .foregroundStyle(HTColor.textMuted)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .htCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: HTSpacing.lg) {
            legendDot(HTColor.success400, "Success")
            legendDot(HTColor.danger300, "Failed")
            legendDot(HTColor.accentSky, "Pending")
        }
        .font(.htCaption)
        .foregroundStyle(HTColor.textMuted)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: HTSpacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Day sheet

    private func daySheet(for date: Date) -> some View {
        let plans = plans(on: date)
        return NavigationStack {
            ScrollView {
                VStack(spacing: HTSpacing.md) {
                    if plans.isEmpty {
                        HTEmptyState(title: "No plans on this day yet.", message: nil, systemImage: "calendar")
                            .htCard()
                    } else {
                        ForEach(plans) { task in
                            Button {
                                detailTask = task
                            } label: {
                                HStack(alignment: .top, spacing: HTSpacing.md) {
                                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                                        Text(task.title)
                                            .font(.htCardTitle)
                                            .foregroundStyle(HTColor.textPrimary)
                                        HTMetaText(task.scheduledRangeText ?? "", task.taskCategory ?? "")
                                    }
                                    Spacer()
                                    StatusPill(status: TaskDisplayStatus(taskStatus: task.taskStatus))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .htCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("+ Add plan") {
                        selectedDay = nil
                        presentAddPlan(on: date)
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                }
                .padding(HTSpacing.screenHorizontal)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle(TaskTimeFormatting.mediumDate(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedDay = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func presentAddPlan(on date: Date) {
        let draft = PlanDraft.new(on: date, defaultDuration: authManager.defaultPlanDurationMinutes ?? 30)
        planFormRequest = PlanFormRequest(draft: draft, editingTaskID: nil)
    }

    // MARK: - Data

    private func plans(on date: Date) -> [HabitTraceTask] {
        let key = TaskTimeFormatting.isoDate(from: date)
        return PlanOrdering.sorted(taskService.tasks.filter { task in
            task.plannedDate == key
                && (categoryFilter == nil || TaskCategory.normalized(task.taskCategory) == categoryFilter)
                && (priorityFilter == nil || task.importance == priorityFilter)
        })
    }

    private func weekStart(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: date)) ?? date
    }

    /// Success emerald, failed rose, pending by category, as in the PWA.
    private func chipPalette(for task: HabitTraceTask) -> ChipPalette {
        switch task.taskStatus {
        case "success": return HTColor.Chip.emerald
        case "failed": return ChipPalette(background: HTColor.danger50, foreground: HTColor.danger700, ring: HTColor.danger100)
        default: break
        }
        switch TaskCategory.normalized(task.taskCategory) {
        case .study: return HTColor.Chip.sky
        case .work: return HTColor.Chip.violet
        case .chores: return HTColor.Chip.amber
        case .fitnessHealth: return HTColor.Chip.emerald
        case .errandsAdmin: return HTColor.Chip.slate
        case .hobbiesLeisure: return HTColor.Chip.fuchsia
        case .social: return HTColor.Chip.cyan
        case .other: return HTColor.Chip.slate
        }
    }

    private func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.validAccessToken()
            await taskService.loadTasks(accessToken: token)
            if taskService.errorMessage != nil, taskService.tasks.isEmpty {
                loadErrorMessage = "Couldn’t load your calendar. Please try again."
            }
        } catch {
            loadErrorMessage = ErrorPresentation.message(for: error)
        }
    }
}

/// Category and priority menus without the status chips, for Calendar.
struct PlansFilterMenus: View {
    @Binding var category: TaskCategory?
    @Binding var priority: Int?

    var body: some View {
        HStack(spacing: HTSpacing.sm) {
            Menu {
                Picker("Category", selection: $category) {
                    Text("All categories").tag(TaskCategory?.none)
                    ForEach(TaskCategory.allCases) { item in
                        Text(item.rawValue).tag(TaskCategory?.some(item))
                    }
                }
            } label: {
                menuLabel(category?.rawValue ?? "All categories", isActive: category != nil)
            }
            .accessibilityLabel("Filter plans by category")

            Menu {
                Picker("Priority", selection: $priority) {
                    Text("All priorities").tag(Int?.none)
                    ForEach(1...5, id: \.self) { level in
                        Text(PlansFilterView.priorityLabel(level)).tag(Int?.some(level))
                    }
                }
            } label: {
                menuLabel(priority.map(PlansFilterView.priorityLabel) ?? "All priorities", isActive: priority != nil)
            }
            .accessibilityLabel("Filter plans by priority")
        }
    }

    private func menuLabel(_ text: String, isActive: Bool) -> some View {
        HStack(spacing: HTSpacing.xs) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .font(.htCaptionStrong)
        .foregroundStyle(isActive ? .white : HTColor.textStrong)
        .padding(.horizontal, HTSpacing.md)
        .frame(minHeight: 36)
        .background(isActive ? HTColor.brand : HTColor.surfaceSecondary)
        .clipShape(Capsule())
    }
}

/// Read-only plan details from the calendar day sheet.
struct PlanDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: HabitTraceTask

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Name", value: task.title)
                if let notes = task.notes, !notes.isEmpty {
                    LabeledContent("Note", value: notes)
                }
                LabeledContent("Category", value: task.taskCategory ?? "Other")
                LabeledContent("Priority", value: PlansFilterView.priorityLabel(task.importance ?? 3))
                if let dateKey = task.plannedDate, let date = TaskTimeFormatting.date(fromISODate: dateKey) {
                    LabeledContent("Date", value: TaskTimeFormatting.mediumDate(date))
                }
                LabeledContent("Time", value: "\(task.scheduledRangeText ?? "—") · \(task.plannedDurationMin ?? 0) min")
                LabeledContent("Status") {
                    StatusPill(status: TaskDisplayStatus(taskStatus: task.taskStatus))
                }
            }
            .navigationTitle("Plan details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back to day") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
