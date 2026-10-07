import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var taskService = TaskService()

    var body: some View {
        NavigationStack {
            Group {
                if taskService.isLoading && taskService.tasks.isEmpty {
                    ProgressView("Loading tasks...")
                } else if let errorMessage = taskService.errorMessage {
                    ContentUnavailableView {
                        Label(
                            "Unable to Load Tasks",
                            systemImage: "exclamationmark.triangle"
                        )
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await loadTasks()
                            }
                        }
                    }
                } else if taskService.tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text(
                            "Your HabitTrace tasks will appear here."
                        )
                    )
                } else {
                    List(taskService.tasks) { task in
                        taskRow(task)
                    }
                    .refreshable {
                        await loadTasks()
                    }
                }
            }
            .navigationTitle("My Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        Task {
                            await authManager.signOut()
                        }
                    }
                }
            }
            .task {
                await loadTasks()
            }
        }
    }

    private func taskRow(_ task: HabitTraceTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)

            if let category = task.taskCategory {
                Text(category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let date = task.plannedDate {
                    Label(date, systemImage: "calendar")
                }

                if let time = task.plannedStartTime {
                    Label(time, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let status = task.taskStatus {
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadTasks() async {
        do {
            let accessToken = try await authManager.validAccessToken()

            await taskService.loadTasks(
                accessToken: accessToken
            )
        } catch {
            taskService.errorMessage = error.localizedDescription
        }
    }
}
