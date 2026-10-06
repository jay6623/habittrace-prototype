import SwiftUI

struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @ObservedObject var taskService: TaskService

    @State private var title = ""
    @State private var notes = ""
    @State private var taskCategory = "General"
    @State private var plannedDate = Date()
    @State private var plannedStartTime = Date()

    @State private var plannedDurationMin = 30
    @State private var importance = 3
    @State private var energyLevel = 3
    @State private var focusLevel = 3

    @State private var isSubmitting = false
    @State private var localErrorMessage: String?

    private let durationOptions = [15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)

                    TextField("Category", text: $taskCategory)

                    TextField(
                        "Notes (Optional)",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section("Schedule") {
                    DatePicker(
                        "Date",
                        selection: $plannedDate,
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Start Time",
                        selection: $plannedStartTime,
                        displayedComponents: .hourAndMinute
                    )

                    Picker(
                        "Duration",
                        selection: $plannedDurationMin
                    ) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text(durationText(minutes))
                                .tag(minutes)
                        }
                    }
                }

                Section("Task Profile") {
                    ratingPicker(
                        title: "Importance",
                        value: $importance
                    )

                    ratingPicker(
                        title: "Energy Level",
                        value: $energyLevel
                    )

                    ratingPicker(
                        title: "Focus Level",
                        value: $focusLevel
                    )
                }

                if let errorMessage = localErrorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await submit()
                        }
                    } label: {
                        HStack {
                            Spacer()

                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Create Task")
                                    .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSubmitting
                    )
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    @ViewBuilder
    private func ratingPicker(
        title: String,
        value: Binding<Int>
    ) -> some View {
        Picker(title, selection: value) {
            ForEach(1...5, id: \.self) { rating in
                Text("\(rating)")
                    .tag(rating)
            }
        }
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(hours)h \(remainingMinutes)m"
    }

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedTitle.isEmpty else {
            localErrorMessage = "Please enter a task title."
            return
        }

        isSubmitting = true
        localErrorMessage = nil

        do {
            let accessToken = try await authManager.validAccessToken()

            let createdDate = Self.dateFormatter.string(
                from: plannedDate
            )

            let createdStartTime = Self.timeFormatter.string(
                from: plannedStartTime
            )

            let totalTasksToday = taskService.tasks.filter {
                $0.plannedDate == createdDate
            }.count + 1

            await taskService.createTask(
                accessToken: accessToken,
                title: trimmedTitle,
                notes: notes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    ? nil
                    : notes.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                taskCategory: taskCategory.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    ? "General"
                    : taskCategory.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                plannedStartTime: createdStartTime,
                plannedDate: createdDate,
                plannedDurationMin: plannedDurationMin,
                importance: importance,
                energyLevel: energyLevel,
                focusLevel: focusLevel,
                totalTasksToday: totalTasksToday
            )

            if let errorMessage = taskService.errorMessage {
                localErrorMessage = errorMessage
            } else {
                dismiss()
            }
        } catch {
            localErrorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
