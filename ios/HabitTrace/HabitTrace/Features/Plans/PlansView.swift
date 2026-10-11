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

/// The Plans screen: header, summary, filter, and the day's plans.
///
/// Renders `PlansViewModel` state and forwards actions. Start, Delete,
/// Add plan, and Edit plan call the view model; Log outcome and the
/// logged edit flow present a placeholder until their sheets exist.
struct PlansScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel: PlansViewModel

    @State private var showingDatePicker = false
    @State private var planFormRequest: PlanFormRequest?
    @State private var pendingAction: PendingAction?
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
                        onPrevious: viewModel.showPreviousDay,
                        onNext: viewModel.showNextDay,
                        onToday: viewModel.showToday,
                        onPickDate: { showingDatePicker = true },
                        onAddPlan: presentNewPlanForm
                    )

                    PlansSummaryStrip(summary: viewModel.summary)
                        .redacted(reason: isAwaitingSelectedDay ? .placeholder : [])
                        .accessibilityHidden(isAwaitingSelectedDay)

                    PlansFilterView(selection: $viewModel.selectedFilter)

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
            .sheet(item: $planFormRequest) { request in
                PlanFormSheet(request: request, viewModel: viewModel) { _ in
                    toast = .success("Plan saved")
                }
            }
            .sheet(item: $pendingAction) { pending in
                PlanActionPlaceholderSheet(action: pending.action, planTitle: pending.item.task.title)
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

    /// True until the selected day's data has loaded: before the first
    /// request starts, during the first load, and during a date change.
    /// Summary tiles are redacted and the list shows the loading card so
    /// neither zeros nor another day's plans are presented as this day's.
    private var isAwaitingSelectedDay: Bool {
        viewModel.loadErrorMessage == nil && viewModel.isShowingStaleContent
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
                onShowAll: { viewModel.selectedFilter = .all }
            )
        } else {
            PlanListView(
                items: viewModel.filteredItems,
                isBusy: viewModel.isBusy,
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
        case .logOutcome, .editLogged:
            pendingAction = PendingAction(action: action, item: item)
        }
    }

    private func delete(_ item: PlanListItem) async {
        if await viewModel.deletePlan(taskID: item.id) {
            toast = .success("Plan deleted")
        }
    }

    /// New plan on the selected day at the next quarter hour, using the
    /// user's saved default duration when one exists.
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

    private var isPresentingDelete: Binding<Bool> {
        Binding(
            get: { planToDelete != nil },
            set: { if !$0 { planToDelete = nil } }
        )
    }

    private struct PendingAction: Identifiable {
        let action: PlanAction
        let item: PlanListItem
        var id: String { "\(item.id)-\(action)" }
    }
}

// MARK: - Date picker sheet

/// Graphical calendar. The selection is committed with Done so browsing
/// months does not trigger a load per tap.
private struct PlansDatePickerSheet: View {
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

// MARK: - Placeholder for flows that arrive in later checkpoints

private struct PlanActionPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: PlanAction
    let planTitle: String

    var body: some View {
        NavigationStack {
            VStack {
                HTEmptyState(
                    title: title,
                    message: "This flow for “\(planTitle)” is coming in the next checkpoint. Nothing has been changed.",
                    systemImage: "hammer"
                )
                .htCard()
                .padding(HTSpacing.screenHorizontal)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(HTColor.surfaceMuted)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch action {
        case .logOutcome: "Log outcome"
        case .edit: "Edit plan"
        case .editLogged: "Edit logged outcome"
        case .start: "Start"
        case .delete: "Delete"
        }
    }
}
