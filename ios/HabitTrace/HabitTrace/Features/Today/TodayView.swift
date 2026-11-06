import SwiftUI

/// Today tab: the shortest path through plan, start, and record.
///
/// Connects the shared `TaskService` and `AuthManager` to
/// `TodayContentView`. Start and Log outcome use the same service calls
/// as Plans, so both screens reflect the server's state.
struct TodayView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    /// Called when the user asks to view or reschedule plans.
    var onViewPlans: () -> Void = {}

    @State private var showingQuickAdd = false
    @State private var showingCoachPlaceholder = false
    @State private var outcomeTarget: HabitTraceTask?
    @State private var isBusy = false
    @State private var toast: HTToastMessage?

    var body: some View {
        NavigationStack {
            TodayContentView(
                tasks: taskService.tasks,
                activeExecutions: taskService.activeExecutions,
                isLoading: taskService.isLoading && taskService.tasks.isEmpty,
                loadErrorMessage: taskService.tasks.isEmpty ? taskService.errorMessage : nil,
                greetingName: authManager.greetingName,
                isBusy: isBusy,
                onQuickAdd: { showingQuickAdd = true },
                onViewPlans: onViewPlans,
                onReload: loadTasks,
                onStart: { task in
                    Task {
                        await start(task)
                    }
                },
                onLogOutcome: { outcomeTarget = $0 }
            )
            .toolbar(.hidden, for: .navigationBar)
            .askCoachOverlay {
                showingCoachPlaceholder = true
            }
            .htToast($toast)
            .task {
                await loadTasks()
            }
            .sheet(isPresented: $showingQuickAdd) {
                CreateTaskView(taskService: taskService)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showingCoachPlaceholder) {
                CoachPlaceholderSheet()
            }
            .sheet(item: $outcomeTarget) { task in
                OutcomeSheet(
                    task: task,
                    activeExecution: taskService.activeExecutions[task.id]
                ) { input in
                    await submitOutcome(for: task, input: input)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadTasks() async {
        do {
            let accessToken = try await authManager.validAccessToken()
            await taskService.loadTasks(accessToken: accessToken)
            // Active executions drive the In progress hero. A failure here
            // keeps the last known map rather than surfacing a second error.
            _ = try? await taskService.fetchActiveExecutions(accessToken: accessToken)
        } catch {
            taskService.errorMessage = error.localizedDescription
        }
    }

    /// `POST /executions/start` through the shared service; the hero and
    /// rows switch to In progress only from the server's response.
    private func start(_ task: HabitTraceTask) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let accessToken = try await authManager.validAccessToken()
            _ = try await taskService.startExecution(accessToken: accessToken, taskId: task.id)
            toast = .success("Started. Your start time was recorded.")
        } catch {
            toast = .error(ErrorPresentation.message(for: error))
        }
    }

    /// Runs the shared outcome flow; the sheet closes only on success.
    private func submitOutcome(for task: HabitTraceTask, input: OutcomeInput) async -> OutcomeSheetResult {
        guard !isBusy else {
            return .failure("Another action is still in progress. Please wait a moment.")
        }
        isBusy = true
        defer { isBusy = false }

        do {
            let accessToken = try await authManager.validAccessToken()
            let result = try await taskService.submitOutcome(
                accessToken: accessToken,
                taskID: task.id,
                input: input
            )

            switch result {
            case .started:
                toast = .success("Plan kept active")
            case .recorded:
                toast = .success("Outcome recorded")
            }
            return .success
        } catch {
            return .failure(ErrorPresentation.message(for: error))
        }
    }
}

/// Placeholder presented by the Ask Coach button until the chat API is wired.
private struct CoachPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                HTEmptyState(
                    title: "AI coach isn't available yet",
                    message: "Ask for a plan, find a better time, or get a nudge. This arrives in a later update.",
                    systemImage: "sparkles"
                )
                .htCard()
                .padding(HTSpacing.screenHorizontal)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(HTColor.surfaceMuted)
            .navigationTitle("AI Coach")
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
}

// `TodayView` itself is not previewed: its `.task` reads the Supabase
// session from the keychain, which stalls inside the preview process.
// Preview `TodayContentView` instead.
