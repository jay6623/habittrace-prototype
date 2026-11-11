import AppIntents
import Foundation
import Supabase

/// Errors surfaced to Siri and Shortcuts. Only
/// `CustomLocalizedStringResourceConvertible` errors are read aloud.
nonisolated enum PlanIntentError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case signedOut
    case emptyTitle
    case titleTooLong
    case missingStartTime
    case invalidDuration
    case backend(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut:
            return "Sign in to HabitTrace first, then try again."
        case .emptyTitle:
            return "Tell me what you want to plan."
        case .titleTooLong:
            return "That title is too long. Keep it under 200 characters."
        case .missingStartTime:
            return "Tell me what time it should start."
        case .invalidDuration:
            return "Plans must be between 5 minutes and 8 hours long."
        case .backend(let message):
            return "HabitTrace couldn't reach your plans. \(message)"
        }
    }
}

/// Resolves the signed-in user's access token outside the SwiftUI tree.
/// The Supabase client persists the session in the keychain, so this works
/// when the system launches the app in the background for an intent.
enum PlanIntentAuth {
    static func accessToken() async throws -> String {
        do {
            return try await SupabaseProvider.client.auth.session.accessToken
        } catch {
            throw PlanIntentError.signedOut
        }
    }
}

/// Pure helpers shared by the intents and their tests.
enum PlanIntentLogic {
    /// At most this many plans are read aloud before "and N more".
    static let spokenPlanLimit = 5

    /// Plans sorted by start time, with unparseable times last.
    static func sorted(_ tasks: [HabitTraceTask]) -> [HabitTraceTask] {
        tasks.sorted { lhs, rhs in
            switch (lhs.startMinutes, rhs.startMinutes) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.title < rhs.title
            }
        }
    }

    /// "You have 2 plans today: Write report at 9:00 AM and Gym at 6:00 PM.
    /// 1 still to go."
    static func todaysPlansDialog(for tasks: [HabitTraceTask]) -> String {
        let plans = sorted(tasks)
        guard !plans.isEmpty else {
            return "You have no plans today."
        }

        let spoken = plans.prefix(spokenPlanLimit).map { task -> String in
            if let time = task.plannedStartTime {
                return "\(task.title) at \(TaskTimeFormatting.displayTime(time))"
            }
            return task.title
        }
        let list: String
        if plans.count > spokenPlanLimit {
            // Leave the list open so "and N more" closes it.
            list = spoken.joined(separator: ", ") + ", and \(plans.count - spokenPlanLimit) more"
        } else {
            list = joinedForSpeech(Array(spoken))
        }

        let noun = plans.count == 1 ? "plan" : "plans"
        var dialog = "You have \(plans.count) \(noun) today: \(list)."

        let remaining = plans.filter { $0.taskStatus == nil || $0.taskStatus == "pending" }.count
        if remaining > 0, remaining < plans.count {
            dialog += " \(remaining) still to go."
        } else if remaining == 0 {
            dialog += " All logged."
        }
        return dialog
    }

    /// A pending plan on the same day with the same title and start time,
    /// so Siri never creates the same plan twice.
    static func duplicate(title: String, startMinutes: Int, in tasks: [HabitTraceTask]) -> HabitTraceTask? {
        let wanted = normalizedTitle(title)
        return tasks.first { task in
            (task.taskStatus == nil || task.taskStatus == "pending")
                && task.startMinutes == startMinutes
                && normalizedTitle(task.title) == wanted
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Added “Write report” to your plans today at 2:00 PM."
    static func addedDialog(for task: HabitTraceTask, today: String) -> String {
        "Added “\(task.title)” to your plans \(whenText(for: task, today: today))."
    }

    /// "“Write report” is already planned today at 2:00 PM, so I didn't add
    /// it again."
    static func duplicateDialog(for task: HabitTraceTask, today: String) -> String {
        "“\(task.title)” is already planned \(whenText(for: task, today: today)), so I didn't add it again."
    }

    private static func whenText(for task: HabitTraceTask, today: String) -> String {
        var parts: [String] = []
        if let date = task.plannedDate {
            if date == today {
                parts.append("today")
            } else if let parsed = TaskTimeFormatting.date(fromISODate: date) {
                parts.append("on \(parsed.formatted(.dateTime.month(.abbreviated).day()))")
            }
        }
        if let time = task.plannedStartTime {
            parts.append("at \(TaskTimeFormatting.displayTime(time))")
        }
        return parts.joined(separator: " ")
    }

    private static func joinedForSpeech(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and \(items[items.count - 1])"
        }
    }
}

/// The intents' single entry point into the app's plan data. It wraps the
/// shared `TaskService` so plans created from Siri appear in Today without
/// a reload, and keeps the intents free of SwiftUI.
@MainActor
final class PlanIntentService {
    typealias TokenProvider = @Sendable () async throws -> String

    enum AddResult: Equatable {
        case created(HabitTraceTask)
        case duplicate(HabitTraceTask)
    }

    private let taskService: TaskService
    private let tokenProvider: TokenProvider
    private let now: @Sendable () -> Date

    nonisolated init(
        taskService: TaskService,
        tokenProvider: @escaping TokenProvider = PlanIntentAuth.accessToken,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.taskService = taskService
        self.tokenProvider = tokenProvider
        self.now = now
    }

    /// Today's plans, sorted by start time.
    func todaysPlans() async throws -> [HabitTraceTask] {
        let token = try await tokenProvider()
        let today = TaskTimeFormatting.isoDate(from: now())
        do {
            return PlanIntentLogic.sorted(try await taskService.fetchTasks(accessToken: token, on: today))
        } catch {
            throw PlanIntentError.backend(ErrorPresentation.message(for: error))
        }
    }

    /// Creates a plan the way Quick Add does (importance, energy, and focus
    /// at 3; `total_tasks_today` from the day's count). Returns `.duplicate`
    /// instead of creating when the same plan already exists, which also
    /// makes a retried intent safe.
    func addPlan(
        title: String,
        start: Date?,
        durationMinutes: Int?,
        category: TaskCategory
    ) async throws -> AddResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlanIntentError.emptyTitle }
        guard trimmed.count <= NaturalLanguagePlanParser.titleLimit else { throw PlanIntentError.titleTooLong }

        let duration = durationMinutes ?? PlanningPreferences.default.defaultDuration
        guard PlanningPreferences.durationRange.contains(duration) else { throw PlanIntentError.invalidDuration }

        let startDate = start ?? TaskTimeFormatting.nextQuarterHour(after: now())
        let dateKey = TaskTimeFormatting.isoDate(from: startDate)
        let storedTime = TaskTimeFormatting.storedTime(from: startDate)
        let components = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        let token = try await tokenProvider()
        do {
            let sameDay = try await taskService.fetchTasks(accessToken: token, on: dateKey)
            if let existing = PlanIntentLogic.duplicate(title: trimmed, startMinutes: startMinutes, in: sameDay) {
                return .duplicate(existing)
            }

            let created = try await taskService.addTask(
                accessToken: token,
                title: trimmed,
                notes: nil,
                taskCategory: category.rawValue,
                plannedStartTime: storedTime,
                plannedDate: dateKey,
                plannedDurationMin: duration,
                importance: 3,
                energyLevel: 3,
                focusLevel: 3,
                totalTasksToday: max(1, sameDay.count + 1)
            )
            return .created(created)
        } catch let error as PlanIntentError {
            throw error
        } catch {
            throw PlanIntentError.backend(ErrorPresentation.message(for: error))
        }
    }

    var todayKey: String {
        TaskTimeFormatting.isoDate(from: now())
    }
}
