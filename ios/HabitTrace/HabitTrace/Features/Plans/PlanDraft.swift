import Foundation

/// Editable fields for creating or editing a plan, matching the PWA's
/// `QuickAddDraft`. Pure value type; the form UI binds to it and the
/// view model turns it into API calls.
struct PlanDraft: Equatable {
    static let durationRange = 5...480
    static let titleLimit = 200
    static let notesLimit = 2000
    static let durationPresets = [15, 30, 45, 60, 90]

    var title = ""
    var notes = ""
    /// The calendar day, normalized to start of day by callers.
    var plannedDate: Date
    /// Minutes since midnight.
    var startMinutes: Int
    var durationMinutes = 30
    var category: TaskCategory = .other
    /// 1 (low) through 5 (high).
    var importance = 3

    /// Defaults for a new plan: the given day at the next quarter hour.
    static func new(
        on date: Date,
        now: Date = .now,
        defaultDuration: Int = 30,
        calendar: Calendar = .current
    ) -> PlanDraft {
        let slot = TaskTimeFormatting.nextQuarterHour(after: now)
        let components = calendar.dateComponents([.hour, .minute], from: slot)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        return PlanDraft(
            plannedDate: calendar.startOfDay(for: date),
            startMinutes: minutes,
            durationMinutes: durationRange.contains(defaultDuration) ? defaultDuration : 30
        )
    }

    /// Edit-mode draft seeded from an existing task.
    init?(task: HabitTraceTask, calendar: Calendar = .current) {
        guard
            let dateKey = task.plannedDate,
            let date = TaskTimeFormatting.date(fromISODate: dateKey)
        else {
            return nil
        }

        title = task.title
        notes = task.notes ?? ""
        plannedDate = calendar.startOfDay(for: date)
        startMinutes = task.startMinutes ?? 0
        durationMinutes = task.plannedDurationMin ?? 30
        category = TaskCategory.normalized(task.taskCategory)
        importance = task.importance ?? 3
    }

    init(
        title: String = "",
        notes: String = "",
        plannedDate: Date,
        startMinutes: Int,
        durationMinutes: Int = 30,
        category: TaskCategory = .other,
        importance: Int = 3
    ) {
        self.title = title
        self.notes = notes
        self.plannedDate = plannedDate
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.category = category
        self.importance = importance
    }

    // MARK: - Derived values for the API

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed notes, or nil when empty, matching the server's normalization.
    var normalizedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stored `"yyyy-MM-dd"` key for `plannedDate`.
    var dateKey: String {
        TaskTimeFormatting.isoDate(from: plannedDate)
    }

    /// Stored 12-hour time such as "2:05 PM", matching the PWA's `toStoredTime`.
    var storedStartTime: String {
        let hour24 = startMinutes / 60
        let minute = startMinutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let meridiem = hour24 < 12 ? "AM" : "PM"
        return "\(hour12):" + String(format: "%02d", minute) + " \(meridiem)"
    }

    /// The slot used for overlap detection.
    var overlapCandidate: PlanOverlap.Candidate {
        PlanOverlap.Candidate(
            dateKey: dateKey,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes
        )
    }

    /// First validation failure, with the PWA's wording, or nil when valid.
    var validationError: String? {
        if trimmedTitle.isEmpty {
            return "Give your plan a name."
        }

        if !Self.durationRange.contains(durationMinutes) {
            return "Choose a duration between 5 and 480 minutes."
        }

        if !(0..<(24 * 60)).contains(startMinutes) {
            return "Choose a valid start time."
        }

        return nil
    }

    var isValid: Bool {
        validationError == nil
    }
}
