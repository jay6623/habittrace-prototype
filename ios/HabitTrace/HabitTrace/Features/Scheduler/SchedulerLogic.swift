import Foundation

/// Pure scheduling helpers behind "Find a time", ported from the PWA's
/// `lib/scheduling.ts` (`findFreeSlots`, `overlappingTasks`) and the
/// scheduler page's date math. Everything here is `nonisolated` so it can
/// be unit-tested off the main actor.
nonisolated enum SchedulerLogic {
    /// Slot granularity and the gap kept around other plans, in minutes.
    static let stepMinutes = 15
    static let bufferMinutes = 15
    /// The scheduler page shows at most this many conflict-free times.
    static let maxSlots = 8

    /// The parts of a task the slot finder needs. Built from
    /// `HabitTraceTask` on the main actor via `PlanSlot(task:)`.
    struct PlanSlot: Equatable, Sendable {
        var id: String
        var dateKey: String?
        var startMinutes: Int?
        var durationMinutes: Int
        var isPending: Bool

        init(id: String, dateKey: String?, startMinutes: Int?, durationMinutes: Int, isPending: Bool) {
            self.id = id
            self.dateKey = dateKey
            self.startMinutes = startMinutes
            self.durationMinutes = durationMinutes
            self.isPending = isPending
        }
    }

    // MARK: - Free slots

    /// Start times (minutes since midnight) on `selected`'s day where it
    /// fits inside `workStart...workEnd` with `buffer` minutes on either
    /// side of every other pending plan that day.
    ///
    /// - `notBefore` cuts off earlier times (the current time when the
    ///   selected date is today). The first candidate is rounded up to the
    ///   next `step`.
    /// - Plans whose start cannot be parsed never conflict, as in the PWA.
    /// - `limit` truncates the result (the page shows at most 8).
    static func freeSlots(
        for selected: PlanSlot,
        among plans: [PlanSlot],
        workStart: String,
        workEnd: String,
        notBefore: Int = 0,
        buffer: Int = bufferMinutes,
        step: Int = stepMinutes,
        limit: Int? = nil
    ) -> [Int] {
        let stop = PlanningPreferences.minutes(from: workEnd)
        let begin = roundUp(max(PlanningPreferences.minutes(from: workStart), notBefore), to: step)
        let duration = max(selected.durationMinutes, 0)
        let others = plans.filter { $0.id != selected.id && $0.isPending && $0.dateKey == selected.dateKey }

        var slots: [Int] = []
        var time = begin
        while time + duration <= stop {
            let fits = others.allSatisfy { other in
                guard let otherStart = other.startMinutes else { return true }
                return time + duration + buffer <= otherStart
                    || time >= otherStart + other.durationMinutes + buffer
            }
            if fits {
                slots.append(time)
                if let limit, slots.count >= limit { break }
            }
            time += step
        }
        return slots
    }

    /// Ids of pending plans that intersect another pending plan on the
    /// same day (half-open ranges, no buffer). Mirrors `overlappingTasks`.
    static func overlappingPendingIDs(_ plans: [PlanSlot]) -> Set<String> {
        let pending = plans.filter { $0.isPending && $0.startMinutes != nil }
        var conflicts = Set<String>()
        for (index, first) in pending.enumerated() {
            for second in pending.dropFirst(index + 1) {
                guard first.dateKey == second.dateKey,
                      let startA = first.startMinutes, let startB = second.startMinutes,
                      startA < startB + second.durationMinutes, startB < startA + first.durationMinutes
                else { continue }
                conflicts.insert(first.id)
                conflicts.insert(second.id)
            }
        }
        return conflicts
    }

    // MARK: - Minutes and clocks

    /// Rounds `minutes` up to the next multiple of `step`.
    static func roundUp(_ minutes: Int, to step: Int) -> Int {
        guard step > 0 else { return minutes }
        return Int((Double(minutes) / Double(step)).rounded(.up)) * step
    }

    /// Minutes since midnight for a `Date` in `calendar`.
    static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// A `Date` at `minutes` after midnight on `day`, for time pickers that
    /// edit minute values.
    static func referenceDate(minutes: Int, on day: Date = .now, calendar: Calendar = .current) -> Date {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day) ?? day
    }

    /// `"HH:mm"` for minutes since midnight.
    static func clock(_ minutes: Int) -> String {
        PlanningPreferences.time(fromMinutes: minutes)
    }

    /// The stored 12-hour form the PWA writes (`toStoredTime`): "9:00 AM".
    static func storedTime(minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        let hour24 = clamped / 60
        let minute = clamped % 60
        let meridiem = hour24 < 12 ? "AM" : "PM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, meridiem)
    }

    // MARK: - Dates and timestamps

    /// `"yyyy-MM-dd"` for a date in `calendar`.
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Start of the day for a `"yyyy-MM-dd"` key, or nil when malformed.
    static func date(fromDateKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 0, minute: 0, second: 0))
    }

    /// A local wall-clock time on `dateKey` as an ISO 8601 timestamp, for
    /// example `2026-11-10T01:00:00Z` for 09:00 in Asia/Kuala_Lumpur.
    /// Mirrors the PWA's `localIso(date, time)` / `parsePlannedStart`.
    static func isoTimestamp(dateKey: String, minutes: Int, calendar: Calendar = .current) -> String? {
        guard let day = date(fromDateKey: dateKey, calendar: calendar),
              let moment = calendar.date(byAdding: .minute, value: minutes, to: day)
        else { return nil }
        return isoFormatter.string(from: moment)
    }

    /// `isoTimestamp(dateKey:minutes:)` for an `"HH:mm"` string.
    static func isoTimestamp(dateKey: String, time: String, calendar: Calendar = .current) -> String? {
        guard PlanningPreferences.validTime(time) != nil else { return nil }
        return isoTimestamp(dateKey: dateKey, minutes: PlanningPreferences.minutes(from: time), calendar: calendar)
    }

    /// Local minutes since midnight for an ISO 8601 timestamp, or nil.
    static func localMinutes(isoTimestamp: String, calendar: Calendar = .current) -> Int? {
        guard let date = TaskTimeFormatting.date(fromISO8601: isoTimestamp) else { return nil }
        return minutesSinceMidnight(date, calendar: calendar)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

@MainActor
extension SchedulerLogic.PlanSlot {
    /// Projects a task onto the fields the slot finder needs.
    init(task: HabitTraceTask) {
        self.init(
            id: task.id,
            dateKey: task.plannedDate,
            startMinutes: task.startMinutes,
            durationMinutes: task.plannedDurationMin ?? 0,
            isPending: task.taskStatus == "pending"
        )
    }
}
