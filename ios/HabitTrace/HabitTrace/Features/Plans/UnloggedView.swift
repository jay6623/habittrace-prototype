import SwiftUI

/// Past plans still waiting for an outcome, newest first. Mirrors the
/// PWA's `/dashboard/habits/unlogged`.
struct UnloggedView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var isBusy = false
    @State private var outcomeTarget: HabitTraceTask?
    @State private var toast: HTToastMessage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    Text("These past plans still need an outcome. Mark each one Completed or Not completed.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textSecondary)

                    if let loadErrorMessage {
                        PlansErrorView(message: loadErrorMessage) {
                            Task { await load() }
                        }
                    } else if isLoading && taskService.tasks.isEmpty {
                        PlansLoadingView()
                    } else if items.isEmpty {
                        HTEmptyState(
                            title: "You're caught up",
                            message: "There are no past plans waiting for a log.",
                            systemImage: "checkmark.circle"
                        )
                        .htCard()
                    } else {
                        LazyVStack(spacing: HTSpacing.md) {
                            ForEach(items) { task in
                                row(task)
                            }
                        }
                    }
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.xxl)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Unlogged plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .htToast($toast)
            .sheet(item: $outcomeTarget) { task in
                OutcomeSheet(task: task, activeExecution: taskService.activeExecutions[task.id]) { input in
                    await submitOutcome(for: task, input: input)
                }
            }
        }
    }

    /// Pending plans dated before today, newest date first, latest time first.
    private var items: [HabitTraceTask] {
        let today = TaskTimeFormatting.isoDate(from: .now)
        return taskService.tasks
            .filter { $0.taskStatus == "pending" && ($0.plannedDate ?? today) < today }
            .sorted { lhs, rhs in
                let lhsDate = lhs.plannedDate ?? ""
                let rhsDate = rhs.plannedDate ?? ""
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return (lhs.startMinutes ?? -1) > (rhs.startMinutes ?? -1)
            }
    }

    private func row(_ task: HabitTraceTask) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            if let dateKey = task.plannedDate, let date = TaskTimeFormatting.date(fromISODate: dateKey) {
                HTEyebrowLabel(text: TaskTimeFormatting.mediumDate(date), color: HTColor.danger700)
            }

            Text(task.title)
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)

            HTMetaText(task.scheduledRangeText ?? "", task.taskCategory ?? "")

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textSecondary)
            }

            Button("Log outcome") {
                outcomeTarget = task
            }
            .buttonStyle(.htPrimary(fullWidth: true))
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.validAccessToken()
            await taskService.loadTasks(accessToken: token)
            if let message = taskService.errorMessage {
                loadErrorMessage = message.isEmpty ? "Couldn’t load unlogged plans." : message
            }
            _ = try? await taskService.fetchActiveExecutions(accessToken: token)
        } catch {
            loadErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func submitOutcome(for task: HabitTraceTask, input: OutcomeInput) async -> OutcomeSheetResult {
        guard !isBusy else { return .failure("Another action is still in progress. Please wait a moment.") }
        isBusy = true
        defer { isBusy = false }

        do {
            let token = try await authManager.validAccessToken()
            let execution = try await taskService.submitOutcome(accessToken: token, taskID: task.id, input: input)
            let detail = OutcomeRequestBuilder.confirmation(for: execution, scheduledEnd: task.scheduledEndText)
            toast = .success("Outcome saved. \(detail)")
            return .success
        } catch {
            return .failure(ErrorPresentation.message(for: error))
        }
    }
}
