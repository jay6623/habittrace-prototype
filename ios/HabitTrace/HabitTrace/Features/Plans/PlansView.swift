import SwiftUI

/// Plans tab entry. Resolves the shared services from the environment and
/// hands them to `PlansScreen`, which owns the view model.
struct PlansView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    var body: some View {
        PlansScreen(
            taskService: taskService,
            accessTokenProvider: authManager.validAccessToken
        )
    }
}

/// The Plans screen: header, summary, filters, and the day's plans.
struct PlansScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService
    @StateObject private var viewModel: PlansViewModel

    @State private var showingDatePicker = false
    @State private var showingUnlogged = false
    @State private var planFormRequest: PlanFormRequest?
    @State private var outcomeTarget: PlanListItem?
    @State private var loggedEditTarget: PlanListItem?
    @State private var planToDelete: PlanListItem?
    @State private var toast: HTToastMessage?

    init(
        taskService: TaskService,
        accessTokenProvider: @escaping PlansViewModel.AccessTokenProvider
    ) {
        _viewModel = StateObject(
            wrappedValue: PlansViewModel(
                taskService: taskService,
                accessTokenProvider: accessTokenProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.xl) {
                    PlansHeader(
                        selectedDate: viewModel.selectedDate,
                        isShowingToday: viewModel.isShowingToday,
                        isLoading: viewModel.isLoading,
                        unloggedCount: unloggedCount,
                        onPrevious: viewModel.showPreviousDay,
                        onNext: viewModel.showNextDay,
                        onToday: viewModel.showToday,
                        onPickDate: { showingDatePicker = true },
                        onAddPlan: presentNewPlanForm,
                        onOpenUnlogged: { showingUnlogged = true }
                    )

                    PlansSummaryStrip(summary: viewModel.summary)
                        .redacted(reason: isAwaitingSelectedDay ? .placeholder : [])
                        .accessibilityHidden(isAwaitingSelectedDay)

                    PlansFilterView(
                        selection: $viewModel.selectedFilter,
                        category: $viewModel.categoryFilter,
                        priority: $viewModel.priorityFilter
                    )

                    content
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.loadIfStale()
            }
            .htToast($toast)
            .onChange(of: viewModel.actionErrorMessage) { _, message in
                guard let message else { return }
                toast = .error(message)
                viewModel.actionErrorMessage = nil
            }
            .sheet(isPresented: $showingDatePicker) {
                PlansDatePickerSheet(selectedDate: viewModel.selectedDate) { date in
                    viewModel.select(date: date)
                }
            }
            .sheet(isPresented: $showingUnlogged, onDismiss: { Task { await viewModel.load() } }) {
                UnloggedView()
                    .environmentObject(authManager)
                    .environmentObject(taskService)
            }
            .sheet(item: $planFormRequest) { request in
                PlanFormSheet(request: request, actions: planFormActions(for: request)) { _ in
                    toast = .success("Plan saved")
                }
            }
            .sheet(item: $outcomeTarget) { item in
                OutcomeSheet(
                    task: item.task,
                    activeExecution: viewModel.activeExecution(for: item.id)
                ) { input in
                    await submitOutcome(for: item, input: input)
                }
            }
            .sheet(item: $loggedEditTarget) { item in
                LoggedPlanEditSheet(task: item.task, viewModel: viewModel) {
                    toast = .success("Logged plan updated")
                }
            }
            .confirmationDialog(
                "Delete this plan?",
                isPresented: isPresentingDelete,
                titleVisibility: .visible,
                presenting: planToDelete
            ) { item in
                Button("Delete plan", role: .destructive) {
                    Task {
                        await delete(item)
                    }
                }
                Button("Keep plan", role: .cancel) {}
            } message: { item in
                Text("“\(item.task.title)” and its execution records will be removed. This cannot be undone.")
            }
        }
    }

    // MARK: - Content states

    private var isAwaitingSelectedDay: Bool {
        viewModel.loadErrorMessage == nil && viewModel.isShowingStaleContent
    }

    private var unloggedCount: Int {
        let today = TaskTimeFormatting.isoDate(from: .now)
        return taskService.tasks.filter { task in
            task.taskStatus == "pending" && (task.plannedDate ?? today) < today
        }.count
    }

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.loadErrorMessage {
            PlansErrorView(message: message) {
                Task {
                    await viewModel.load()
                }
            }
        } else if isAwaitingSelectedDay || (viewModel.isLoading && viewModel.tasks.isEmpty) {
            PlansLoadingView()
        } else if let emptyState = viewModel.emptyState {
            PlansEmptyStateView(
                state: emptyState,
                onAddPlan: presentNewPlanForm,
                onShowAll: viewModel.clearFilters
            )
        } else {
            PlanListView(
                items: viewModel.filteredItems,
                isBusy: viewModel.isBusy,
                startingTaskID: viewModel.startingTaskID,
                onAction: handle
            )
        }
    }

    // MARK: - Actions

    private func handle(_ action: PlanAction, for item: PlanListItem) {
        switch action {
        case .start:
            Task {
                if await viewModel.startPlan(taskID: item.id) != nil {
                    toast = .success("Started. Your start time was recorded.")
                }
            }
        case .delete:
            planToDelete = item
        case .edit:
            presentEditForm(for: item)
        case .logOutcome:
            outcomeTarget = item
        case .editLogged:
            loggedEditTarget = item
        }
    }

    /// Runs the shared outcome flow and reports back to the sheet, which
    /// closes only on success. Toast wording follows the PWA.
    private func submitOutcome(for item: PlanListItem, input: OutcomeInput) async -> OutcomeSheetResult {
        if let execution = await viewModel.submitOutcome(taskID: item.id, input: input) {
            let detail = OutcomeRequestBuilder.confirmation(for: execution, scheduledEnd: item.task.scheduledEndText)
            toast = .success("Outcome saved. \(detail)")
            return .success
        }

        let message = viewModel.actionErrorMessage ?? "Couldn’t save this outcome. Please try again."
        viewModel.actionErrorMessage = nil
        return .failure(message)
    }

    private func delete(_ item: PlanListItem) async {
        if await viewModel.deletePlan(taskID: item.id) {
            toast = .success("Plan deleted")
        }
    }

    private func presentNewPlanForm() {
        let draft = PlanDraft.new(
            on: viewModel.selectedDate,
            defaultDuration: authManager.defaultPlanDurationMinutes ?? 30
        )
        planFormRequest = PlanFormRequest(draft: draft, editingTaskID: nil)
    }

    private func presentEditForm(for item: PlanListItem) {
        guard let draft = PlanDraft(task: item.task) else {
            toast = .error("This plan is missing a date and can't be edited here.")
            return
        }
        planFormRequest = PlanFormRequest(draft: draft, editingTaskID: item.id)
    }

    private func planFormActions(for request: PlanFormRequest) -> PlanFormActions {
        PlanFormActions(
            overlappingPlans: { draft, excludingTaskID in
                try await viewModel.overlappingPlans(for: draft, excludingTaskID: excludingTaskID)
            },
            save: { draft in
                let saved: HabitTraceTask?
                if let taskID = request.editingTaskID {
                    saved = await viewModel.updatePlan(taskID: taskID, with: draft)
                } else {
                    saved = await viewModel.createPlan(from: draft)
                }
                if let saved {
                    return .saved(saved)
                }
                let message = viewModel.actionErrorMessage ?? "Couldn't save this plan. Please try again."
                viewModel.actionErrorMessage = nil
                return .failed(message)
            }
        )
    }

    private var isPresentingDelete: Binding<Bool> {
        Binding(
            get: { planToDelete != nil },
            set: { if !$0 { planToDelete = nil } }
        )
    }
}

// MARK: - Date picker sheet

/// Graphical calendar. The selection is committed with Done so browsing
/// months does not trigger a load per tap.
struct PlansDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        _draft = State(initialValue: selectedDate)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Date", selection: $draft, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, HTSpacing.sm)

                Spacer()
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect(draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
