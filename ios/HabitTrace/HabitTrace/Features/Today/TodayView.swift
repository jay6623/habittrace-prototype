import SwiftUI

/// Today tab: the shortest path through plan, start, and record.
///
/// Connects the shared `TaskService` and `AuthManager` to
/// `TodayContentView`. The only write performed here is the existing
/// one-shot completion in `TaskService.completeTask`.
struct TodayView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    /// Called when the user asks to view or reschedule plans.
    var onViewPlans: () -> Void = {}

    @State private var showingQuickAdd = false
    @State private var showingCoachPlaceholder = false
    @State private var taskToComplete: HabitTraceTask?
    @State private var isCompleting = false
    @State private var toast: HTToastMessage?

    var body: some View {
        NavigationStack {
            TodayContentView(
                tasks: taskService.tasks,
                isLoading: taskService.isLoading && taskService.tasks.isEmpty,
                loadErrorMessage: taskService.tasks.isEmpty ? taskService.errorMessage : nil,
                greetingName: authManager.greetingName,
                isCompleting: isCompleting,
                onQuickAdd: { showingQuickAdd = true },
                onViewPlans: onViewPlans,
                onReload: loadTasks,
                onComplete: { taskToComplete = $0 }
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
            .confirmationDialog(
                "Mark this plan as completed?",
                isPresented: isPresentingCompletion,
                titleVisibility: .visible,
                presenting: taskToComplete
            ) { task in
                Button("Mark complete") {
                    Task {
                        await complete(task)
                    }
                }
            } message: { task in
                Text(task.title)
            }
        }
    }

    // MARK: - Actions

    private var isPresentingCompletion: Binding<Bool> {
        Binding(
            get: { taskToComplete != nil },
            set: { if !$0 { taskToComplete = nil } }
        )
    }

    private func loadTasks() async {
        do {
            let accessToken = try await authManager.validAccessToken()
            await taskService.loadTasks(accessToken: accessToken)
        } catch {
            taskService.errorMessage = error.localizedDescription
        }
    }

    /// Logs a completed execution through the existing service call and
    /// reports the real outcome in a toast.
    private func complete(_ task: HabitTraceTask) async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            let accessToken = try await authManager.validAccessToken()
            await taskService.completeTask(accessToken: accessToken, taskId: task.id)

            if let errorMessage = taskService.errorMessage {
                toast = .error(errorMessage)
            } else {
                toast = .success("Marked \"\(task.title)\" complete")
            }
        } catch {
            toast = .error(error.localizedDescription)
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
