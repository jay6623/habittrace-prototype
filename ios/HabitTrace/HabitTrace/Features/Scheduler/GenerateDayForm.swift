import Foundation

/// One task the user wants placed, before any time is chosen. Mirrors the
/// PWA generator's `TaskEditor`; categories are stored as their raw
/// `task_category` string so this stays `nonisolated`.
nonisolated struct GenerateDayTaskDraft: Identifiable, Equatable, Sendable {
    static let titleLimit = 200
    static let durationOptions = [15, 30, 45, 60, 90, 120, 180]
    static let levelOptions = [1, 2, 3, 4, 5]

    let id: UUID
    var title = ""
    var category: String?
    var durationMinutes = 30
    var importance = 3
    var difficulty = 3
    var requiredEnergy = 3
    var requiredFocus = 3
    /// Minutes since midnight on the selected day, when a deadline is set.
    var deadlineMinutes: Int?
    var isFixedTime = false
    /// Minutes since midnight on the selected day, when fixed.
    var fixedStartMinutes: Int?

    init(id: UUID = UUID()) {
        self.id = id
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The generator form: day, availability window, buffer, and tasks.
/// Validation messages match the PWA exactly.
nonisolated struct GenerateDayForm: Equatable, Sendable {
    static let bufferOptions = [0, 5, 10, 15, 20, 30]

    /// `"yyyy-MM-dd"`.
    var dateKey: String
    /// `"HH:mm"`.
    var dayStart: String
    var dayEnd: String
    var bufferMinutes = 15
    var tasks: [GenerateDayTaskDraft]

    init(dateKey: String, dayStart: String, dayEnd: String, bufferMinutes: Int = 15, tasks: [GenerateDayTaskDraft] = [GenerateDayTaskDraft()]) {
        self.dateKey = dateKey
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.bufferMinutes = bufferMinutes
        self.tasks = tasks
    }

    /// Tasks that have a title; blank rows are ignored, as in the PWA.
    var titledTasks: [GenerateDayTaskDraft] {
        tasks.filter { !$0.trimmedTitle.isEmpty }
    }

    /// First validation failure in the PWA's order, or nil when valid.
    var validationError: String? {
        let clean = titledTasks
        if clean.isEmpty {
            return "Add at least one task with a title."
        }
        if let missing = clean.first(where: { ($0.category ?? "").isEmpty }) {
            return "Choose a category for \(missing.trimmedTitle)."
        }
        if let invalidFixed = clean.first(where: { $0.isFixedTime && $0.fixedStartMinutes == nil }) {
            return "Choose a fixed time for \(invalidFixed.trimmedTitle)."
        }
        if dayEnd <= dayStart {
            return "Your day must end after it starts."
        }
        return nil
    }

    var isValid: Bool { validationError == nil }

    /// The generate request, or nil when the form is invalid.
    func makeRequest(timezoneName: String, calendar: Calendar = .current) -> DailyScheduleGenerateRequest? {
        guard isValid else { return nil }
        let requests = titledTasks.map { task in
            DailyScheduleTaskRequest(
                clientId: task.id.uuidString.lowercased(),
                title: task.trimmedTitle,
                estimatedDurationMinutes: task.durationMinutes,
                deadlineAt: task.deadlineMinutes.flatMap { SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: $0, calendar: calendar) },
                importance: task.importance,
                category: task.category ?? "",
                difficulty: task.difficulty,
                requiredEnergy: task.requiredEnergy,
                requiredFocus: task.requiredFocus,
                isFixedTime: task.isFixedTime,
                fixedStart: task.isFixedTime
                    ? task.fixedStartMinutes.flatMap { SchedulerLogic.isoTimestamp(dateKey: dateKey, minutes: $0, calendar: calendar) }
                    : nil
            )
        }
        return DailyScheduleGenerateRequest(
            selectedDate: dateKey,
            timezoneName: timezoneName,
            dayStart: dayStart,
            dayEnd: dayEnd,
            minimumBufferMinutes: bufferMinutes,
            tasks: requests
        )
    }
}
