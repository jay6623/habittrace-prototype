import Foundation

/// Parsing and formatting for the string-based task schedule fields.
///
/// The backend stores `planned_start_time` as free text and accepts both
/// `"2:00 PM"` and `"14:00"`. The PWA writes the 12-hour form, so new tasks
/// from iOS use the same form to keep the data consistent. `planned_date`
/// is always `"yyyy-MM-dd"`.
enum TaskTimeFormatting {
    // MARK: Parsing

    /// Minutes since midnight for a stored time, or `nil` if unparseable.
    /// Accepts `"2:00 PM"`, `"2:00PM"`, `"14:00"`, and `"9:5 am"`.
    static func minutesSinceMidnight(from storedTime: String) -> Int? {
        let trimmed = storedTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: timePattern) else {
            return nil
        }

        guard
            var hour = Int(match.output.1),
            let minute = Int(match.output.2),
            minute <= 59
        else {
            return nil
        }

        if let meridiem = match.output.3?.uppercased() {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "AM", hour == 12 { hour = 0 }
            if meridiem == "PM", hour != 12 { hour += 12 }
        } else {
            guard hour <= 23 else { return nil }
        }

        return hour * 60 + minute
    }

    /// Combines a stored date and time into a `Date` in the current calendar.
    static func plannedStart(date storedDate: String?, time storedTime: String?) -> Date? {
        guard
            let storedDate,
            let storedTime,
            let day = isoDateFormatter.date(from: storedDate),
            let minutes = minutesSinceMidnight(from: storedTime)
        else {
            return nil
        }

        return Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: day
        )
    }

    /// Parses a stored `"yyyy-MM-dd"` date at the start of that day.
    static func date(fromISODate storedDate: String) -> Date? {
        isoDateFormatter.date(from: storedDate)
    }

    // MARK: Storage formatting

    /// `"yyyy-MM-dd"` in the current time zone, matching the PWA's
    /// `localDateString`.
    static func isoDate(from date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    /// Stored 12-hour time such as `"2:00 PM"`, matching the PWA's
    /// `toStoredTime`.
    static func storedTime(from date: Date) -> String {
        storedTimeFormatter.string(from: date)
    }

    // MARK: Display formatting

    /// Locale-aware short time for display, such as "2:00 PM" or "14:00".
    /// Falls back to the raw string when it cannot be parsed.
    static func displayTime(_ storedTime: String) -> String {
        guard
            let minutes = minutesSinceMidnight(from: storedTime),
            let date = Calendar.current.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: .now
            )
        else {
            return storedTime
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Short display time for a `Date`.
    static func displayTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Human duration such as "30 min", "1 hr", or "1 hr 30 min".
    static func durationText(minutes: Int) -> String {
        guard minutes >= 60 else {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        if remainder == 0 {
            return "\(hours) hr"
        }

        return "\(hours) hr \(remainder) min"
    }

    /// Long header date such as "Wednesday, October 7".
    static func headerDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }

    /// Rounds up to the next 15-minute slot, matching the PWA's Quick Add
    /// default start time.
    static func nextQuarterHour(after date: Date = .now) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = components.minute ?? 0
        let roundedMinute = Int((Double(minute) / 15).rounded(.up)) * 15
        let base = calendar.date(bySettingHour: components.hour ?? 0, minute: 0, second: 0, of: date) ?? date
        return calendar.date(byAdding: .minute, value: roundedMinute, to: base) ?? date
    }

    // MARK: Private

    private static let timePattern = /^(\d{1,2}):(\d{1,2})\s*([AaPp][Mm])?$/

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let storedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
