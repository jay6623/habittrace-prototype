import Foundation
import Supabase

/// The PWA's `planning_preferences` stored in Supabase user metadata.
///
/// Mirrors `lib/preferences.ts`: invalid or missing values fall back to
/// the same defaults, and times are `"HH:mm"` strings.
nonisolated struct PlanningPreferences: Equatable, Sendable {
    static let durationRange = 5...480
    static let `default` = PlanningPreferences(defaultDuration: 30, workStart: "09:00", workEnd: "22:00")

    var defaultDuration: Int
    var workStart: String
    var workEnd: String

    init(defaultDuration: Int, workStart: String, workEnd: String) {
        self.defaultDuration = defaultDuration
        self.workStart = workStart
        self.workEnd = workEnd
    }

    /// Reads `metadata["planning_preferences"]`, tolerating missing keys,
    /// wrong types, and out-of-range values exactly like the PWA.
    init(metadata: [String: AnyJSON]) {
        let raw = metadata["planning_preferences"]?.objectValue ?? [:]

        let duration: Int?
        if let integer = raw["defaultDuration"]?.intValue {
            duration = integer
        } else if let double = raw["defaultDuration"]?.doubleValue {
            duration = Int(double)
        } else {
            duration = nil
        }

        self.init(
            defaultDuration: duration.flatMap { Self.durationRange.contains($0) ? $0 : nil } ?? Self.default.defaultDuration,
            workStart: Self.validTime(raw["workStart"]?.stringValue) ?? Self.default.workStart,
            workEnd: Self.validTime(raw["workEnd"]?.stringValue) ?? Self.default.workEnd
        )
    }

    /// Encoded as the PWA stores it: `{ defaultDuration, workStart, workEnd }`.
    var metadataValue: AnyJSON {
        .object([
            "defaultDuration": .integer(defaultDuration),
            "workStart": .string(workStart),
            "workEnd": .string(workEnd),
        ])
    }

    /// First validation failure with the PWA's wording, or nil.
    var validationError: String? {
        if !Self.durationRange.contains(defaultDuration) {
            return "Default plan duration must be between 5 and 480 minutes."
        }
        if workEnd <= workStart {
            return "Daily availability must end after it starts."
        }
        return nil
    }

    // MARK: - Time helpers

    static func validTime(_ value: String?) -> String? {
        guard let value, value.wholeMatch(of: /^(?:[01]\d|2[0-3]):[0-5]\d$/) != nil else {
            return nil
        }
        return value
    }

    /// Minutes since midnight for an `"HH:mm"` string.
    static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// `"HH:mm"` for minutes since midnight.
    static func time(fromMinutes minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Friendly copy such as "9:00 AM", matching `formatPreferenceTime`.
    @MainActor
    static func displayTime(_ time: String, calendar: Calendar = .current) -> String {
        let minutes = minutes(from: time)
        guard let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) else {
            return time
        }
        return TaskTimeFormatting.displayTime(date)
    }
}
