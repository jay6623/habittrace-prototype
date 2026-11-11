import Foundation

/// What a free-form request said about a plan. Every field is set only when
/// the text actually contained it, so callers can tell stated values from
/// defaults. Pure value; no networking or persistence.
nonisolated struct PlanUtteranceInterpretation: Equatable, Sendable {
    enum CategorySource: Equatable, Sendable {
        /// Named outright ("category is Study", "under Work").
        case stated
        /// Guessed from words in the title ("workout" → Fitness & Health).
        case inferred
    }

    /// Cleaned title. Empty when nothing but time, duration, and date cues
    /// remained.
    var title = ""
    /// Start of the requested day, when the text named one.
    var day: Date?
    /// Minutes since midnight, when the text gave a precise time.
    var startMinutes: Int?
    /// A time expression that needs a follow-up question ("tonight",
    /// "later", a bare "at 5" with no AM or PM). Set only when no precise
    /// time was found.
    var vagueTime: String?
    var durationMinutes: Int?
    var category: TaskCategory?
    var categorySource: CategorySource?
    /// True when a title was explicitly labelled ("called X", "title is X").
    var titleWasLabelled = false

    /// True when the text carried more than a bare title.
    var recognizedAnyCue: Bool {
        day != nil || startMinutes != nil || vagueTime != nil
            || durationMinutes != nil || categorySource == .stated || titleWasLabelled
    }

    /// True when the leftover title still looks like scheduling language
    /// rather than a name, so it should not be saved as-is.
    var titleLooksUnreliable: Bool {
        NaturalLanguagePlanParser.titleLooksUnreliable(title)
    }
}

/// Rule-based parser for spoken or typed plan requests such as
/// "Schedule a 20-minute study session at 5 PM" or "Remind me to review my
/// slides tonight". It extracts dates, times, durations, and categories and
/// returns whatever is left as the title. Patterns are deliberately explicit;
/// anything it cannot read stays in the title where the confirmation step
/// exposes it.
nonisolated enum NaturalLanguagePlanParser {
    static let titleLimit = 200

    static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> PlanUtteranceInterpretation {
        var work = text.replacingOccurrences(of: "\u{2019}", with: "'")
        work = work.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var result = PlanUtteranceInterpretation()
        let today = calendar.startOfDay(for: now)

        // Labelled fields first, so "the start time is 5 PM" becomes "at 5 PM"
        // and the generic patterns below can read it.
        if let captures = extract(labelledTitlePattern, from: &work), let labelled = captures.first ?? nil {
            result.title = cleanLabelledTitle(labelled)
            result.titleWasLabelled = !result.title.isEmpty
        }
        work = replace(#"\b(?:the\s+)?start(?:ing)?\s+time(?:\s*:|\s+is|\s+of|\s+should\s+be)\s*"#, in: work, with: " at ")
        work = replace(#"\b(?:the\s+)?time(?:\s*:|\s+is|\s+should\s+be)\s*"#, in: work, with: " at ")
        work = replace(#"\b(?:it\s+)?(?:starts|starting|begins|beginning)\s+(?:at\s+)?"#, in: work, with: " at ")
        work = replace(#"\b(?:the\s+)?(?:duration|length)(?:\s*:|\s+is|\s+of|\s+should\s+be)\s*"#, in: work, with: " for ")
        work = replace(#"\b(?:it\s+)?(?:takes|lasts|lasting|taking)\s+"#, in: work, with: " for ")

        if let stated = extractStatedCategory(from: &work) {
            result.category = stated
            result.categorySource = .stated
        }

        // Dates before times so "Nov 20" and "2026-12-05" are never read as
        // clock values.
        result.day = extractDate(from: &work, today: today, calendar: calendar)

        result.durationMinutes = extractDuration(from: &work)

        let dayparts = detectDayparts(in: work)
        let time = extractTime(from: &work, dayparts: dayparts)
        result.startMinutes = time.minutes
        if time.minutes == nil {
            result.vagueTime = time.ambiguous
        }

        // Daypart words resolve times above; on their own they are a vague
        // time. "tonight" and "this …" also pin the day to today.
        for daypart in dayparts {
            if daypart.impliesToday, result.day == nil {
                result.day = today
            }
            work = replace(daypart.pattern, in: work, with: " ")
        }
        if result.startMinutes == nil, result.vagueTime == nil, let phrase = dayparts.first?.phrase {
            result.vagueTime = phrase
        }
        if let later = extract(#"\b((?:sometime\s+)?later(?:\s+today)?|soon|at\s+some\s+point|whenever)\b"#, from: &work) {
            if result.startMinutes == nil, result.vagueTime == nil {
                result.vagueTime = (later.first ?? nil)?.lowercased() ?? "later"
            }
            if result.day == nil { result.day = today }
        }

        if !result.titleWasLabelled {
            result.title = cleanTitle(work)
        }

        if result.category == nil, let guess = inferCategory(from: result.title) {
            result.category = guess
            result.categorySource = .inferred
        }

        return result
    }

    // MARK: - Title

    private static let labelledTitlePattern =
        #"\b(?:(?:the\s+)?(?:title|name)(?:\s*:|\s+is|\s+should\s+be)|called|named|titled)\s*(.+?)\s*(?=,|;|\.(?:\s|$)|\s+and\s+(?:the\s+|it\s+)?(?:start|time|duration|length|category|takes|lasts)\b|\s+(?:the\s+)?(?:start(?:ing)?\s+time|time|duration|length|category)(?:\s*:|\s+is|\s+of|\s+should)|\s+(?:at|for|on|under|tomorrow|today|tonight|next|this|starting|from)\b|$)"#

    private static func cleanLabelledTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        return capitalizingFirstLetter(title)
    }

    /// Strips commands, app mentions, and connector words from whatever the
    /// field patterns left behind.
    static func cleanTitle(_ remainder: String) -> String {
        var title = remainder
        for pattern in fillerPatterns {
            title = replace(pattern, in: title, with: " ")
        }
        title = title.replacing(/[,;]+/, with: " ")
        title = title.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        var changed = true
        while changed {
            changed = false
            for pattern in leadingPatterns {
                let stripped = replace(pattern, in: title, with: "")
                if stripped != title {
                    title = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
            for pattern in trailingPatterns {
                let stripped = replace(pattern, in: title, with: "")
                if stripped != title {
                    title = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        title = title.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return capitalizingFirstLetter(title)
    }

    private static let fillerPatterns = [
        #"\b(?:in|to|on|into|with|using|from|through)\s+(?:my\s+|the\s+)?habit\s?trace(?:\s+app)?\b"#,
        #"\bhabit\s?trace(?:\s+app)?\b"#,
        #"\b(?:to|on|in|into)\s+(?:my|the)\s+(?:plans?|schedule|calendar|list|day|agenda|to-?dos?)\b"#,
        #"\bas\s+a\s+(?:new\s+)?(?:task|plan|reminder|event)\b"#,
        #"\bfor\s+me\b"#,
    ]

    private static let leadingPatterns = [
        #"^(?:please|hey|hi|ok|okay|so|um|uh|and|also|then|just|now)\b[\s,]*"#,
        #"^(?:can|could|would|will)\s+you\s+(?:please\s+)?"#,
        #"^(?:schedule|add|create|make|set\s+up|set|put|book|plan|log|record|note|start|save|enter|new|block(?:\s+out|\s+off)?)\s+(?:in\s+)?(?:me\s+)?(?:a\s+new\s+|another\s+|a\s+|an\s+|the\s+|some\s+)?"#,
        #"^remind\s+me\s+(?:to\s+|about\s+|of\s+)?"#,
        #"^i\s+(?:need|want|have|'d\s+like|would\s+like|am\s+going|'m\s+going|plan|intend|got)\s+to\s+"#,
        #"^(?:task|plan|event|reminder|session|item|entry|to-?do)(?:\s*:|\s+(?:called|named|titled|for|to))\s*"#,
        #"^(?:called|named|titled)\s+"#,
        #"^(?:a|an)\s+"#,
        #"^(?:and|to|for|at|on|in|with|of|that|which)\b\s*"#,
        #"^[-–—:.,;]+\s*"#,
    ]

    private static let trailingPatterns = [
        #"\s+(?:task|plan|event|reminder|item|entry|to-?do)\s*$"#,
        #"\s+(?:and|to|for|at|on|in|with|of|the|a|an|is|it|that|which|please|then)\s*$"#,
        #"\s*[-–—:.,;]+\s*$"#,
    ]

    /// Words that only ever describe scheduling, not a plan's name.
    static func titleLooksUnreliable(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.count > titleLimit { return true }
        if trimmed.split(separator: " ").count > 12 { return true }
        let cue = try! Regex(#"\b(?:a\.?m|p\.?m|minutes?|mins?|hours?|hrs?|o'?clock|duration|category|title\s+is|start\s+time|tomorrow|today|tonight)\b|\d{1,2}:\d{2}"#).ignoresCase()
        return trimmed.firstMatch(of: cue) != nil
    }

    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Category

    private static let categoryAliases: [(TaskCategory, String)] = [
        (.fitnessHealth, #"fitness\s*(?:and|&|/)\s*health|health\s*(?:and|&|/)\s*fitness|fitness|health|exercise"#),
        (.errandsAdmin, #"errands?\s*(?:and|&|/)\s*admin(?:istration)?|admin(?:istration|istrative)?|errands?"#),
        (.hobbiesLeisure, #"hobbies\s*(?:and|&|/)\s*leisure|hobbies|hobby|leisure|fun"#),
        (.study, #"study(?:ing)?|studies|school|academics?"#),
        (.work, #"work(?:ing)?|job|office"#),
        (.chores, #"chores?|housework|cleaning"#),
        (.social, #"social|friends|family"#),
        (.other, #"other|misc(?:ellaneous)?|general"#),
    ]

    private static func extractStatedCategory(from text: inout String) -> TaskCategory? {
        let names = categoryAliases.map { "(?:\($0.1))" }.joined(separator: "|")
        let patterns = [
            #"\b(?:the\s+)?category(?:\s*:|\s+is|\s+should\s+be|\s+of)\s*(?:the\s+)?("# + names + #")(?:\s+category)?\b"#,
            #"\b(?:categori[sz]ed?|filed?|tagged?)\s+(?:as|under)\s+(?:the\s+)?("# + names + #")(?:\s+category)?\b"#,
            #"\bunder\s+(?:the\s+)?("# + names + #")(?:\s+category)?\b"#,
            #"\bin\s+(?:the\s+)?("# + names + #")\s+category\b"#,
        ]
        for pattern in patterns {
            if let captures = extract(pattern, from: &text), let name = captures.first ?? nil {
                return category(matchingAlias: String(name))
            }
        }
        return nil
    }

    private static func category(matchingAlias alias: String) -> TaskCategory? {
        for (category, pattern) in categoryAliases {
            let regex = try! Regex("^(?:" + pattern + ")$").ignoresCase()
            if alias.trimmingCharacters(in: .whitespaces).wholeMatch(of: regex) != nil {
                return category
            }
        }
        return nil
    }

    private static let categoryKeywords: [(TaskCategory, String)] = [
        (.fitnessHealth, #"work\s?out|gym|run(?:ning)?|jog(?:ging)?|yoga|exercise|walk(?:ing)?|swim(?:ming)?|stretch(?:ing)?|training|cycling|bike|biking|hike|hiking|pilates|lift(?:ing)?|cardio|meditat(?:e|ion)|sleep|nap"#),
        (.study, #"study(?:ing)?|homework|exams?|quiz|lecture|class(?:es)?|revis(?:e|ion)|read(?:ing)?|chapter|algorithms?|assignment|essay|thesis|capstone|research|course(?:work)?|flashcards|learn(?:ing)?|practice\s+problems|tutorial|notes|lab"#),
        (.work, #"work|meeting|stand-?up|report|emails?|client|presentation|slides|deck|deadline|project|sprint|interview|shift|office|invoice|proposal|code\s+review|pull\s+request|deploy"#),
        (.chores, #"laundry|dishes|clean(?:ing)?|vacuum|tidy(?:ing)?|cook(?:ing)?|meal\s+prep|trash|garbage|mop(?:ping)?|iron(?:ing)?|organi[sz]e|declutter"#),
        (.errandsAdmin, #"groceries|grocery|errands?|bank|pharmacy|appointment|dentist|doctor|dmv|bills?|pay|taxes|post\s+office|pick\s+up|drop\s+off|renew|insurance|passport|paperwork|forms?"#),
        (.hobbiesLeisure, #"guitar|piano|paint(?:ing)?|draw(?:ing)?|gam(?:e|es|ing)|movie|novel|knit(?:ting)?|garden(?:ing)?|photography|hobby|chess|music|podcast|show|netflix"#),
        (.social, #"dinner|lunch|coffee|brunch|call\s+(?:mom|dad|grandma|grandpa|my)|hang\s+out|party|date\s+night|friends?|family|catch\s+up|birthday|visit"#),
    ]

    /// Best-effort category from the title's words. Fitness is checked first
    /// so "work out" is never read as Work.
    static func inferCategory(from title: String) -> TaskCategory? {
        for (category, pattern) in categoryKeywords {
            let regex = try! Regex(#"\b(?:"# + pattern + #")\b"#).ignoresCase()
            if title.firstMatch(of: regex) != nil {
                return category
            }
        }
        return nil
    }

    // MARK: - Duration

    private static let numberWord = #"\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty[- ]five|forty|fifty|sixty|ninety|an?"#

    private static func number(from text: String?) -> Double? {
        guard let text else { return nil }
        let token = text.lowercased().replacingOccurrences(of: "-", with: " ")
        if let value = Double(token) { return value }
        let words: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty five": 45,
            "fifty": 50, "sixty": 60, "ninety": 90,
        ]
        return words[token]
    }

    private static func extractDuration(from text: inout String) -> Int? {
        let lead = #"\b(?:for\s+|lasting\s+|taking\s+|of\s+)?"#
        if extract(lead + #"(?:an?\s+)?hour\s+and\s+a\s+half\b"#, from: &text) != nil {
            return 90
        }
        if let captures = extract(lead + #"("# + numberWord + #")\s+and\s+a\s+half\s+hours?\b"#, from: &text),
           let hours = number(from: captures.first ?? nil) {
            return Int(hours * 60) + 30
        }
        if extract(lead + #"(?:half\s+an\s+hour|a\s+half[- ]hour|half[- ]hour)\b"#, from: &text) != nil {
            return 30
        }
        if let captures = extract(
            lead + #"("# + numberWord + #")\s*[- ]?\s*(?:hours?|hrs?|h)(?:[- ]long)?\b(?:\s*(?:and\s+)?("# + numberWord + #")\s*[- ]?\s*(?:minutes?|mins?|min)\b)?"#,
            from: &text
        ), let hours = number(from: captures.first ?? nil) {
            let minutes = number(from: captures.count > 1 ? captures[1] : nil) ?? 0
            return Int((hours * 60 + minutes).rounded())
        }
        if let captures = extract(lead + #"("# + numberWord + #")\s*[- ]?\s*(?:minutes?|mins?|min)(?:[- ]long)?\b"#, from: &text),
           let minutes = number(from: captures.first ?? nil) {
            return Int(minutes.rounded())
        }
        return nil
    }

    // MARK: - Time

    private struct Daypart {
        enum Kind { case morning, afternoon, evening }
        let kind: Kind
        let phrase: String
        let pattern: String
        let impliesToday: Bool
    }

    private static func detectDayparts(in text: String) -> [Daypart] {
        let definitions: [(Daypart.Kind, String)] = [
            (.morning, #"\b(?:in\s+the\s+|this\s+|tomorrow\s+)?morning\b"#),
            (.afternoon, #"\b(?:in\s+the\s+|this\s+|tomorrow\s+)?afternoon\b"#),
            (.evening, #"\b(?:in\s+the\s+|this\s+|tomorrow\s+)?evening\b|\btonight\b|\bat\s+night\b"#),
        ]
        var found: [Daypart] = []
        for (kind, pattern) in definitions {
            let regex = try! Regex(pattern).ignoresCase()
            if let match = text.firstMatch(of: regex) {
                let matched = String(text[match.range]).lowercased()
                let impliesToday = matched == "tonight" || matched.hasPrefix("this ") || matched == "at night"
                // A bare daypart word reads badly in a follow-up question
                // ("What time morning…"), so it is spoken with a preposition.
                let phrase = ["morning", "afternoon", "evening"].contains(matched) ? "in the \(matched)" : matched
                found.append(Daypart(kind: kind, phrase: phrase, pattern: pattern, impliesToday: impliesToday))
            }
        }
        return found
    }

    private static let timeLead = #"\b(?:at\s+|around\s+|by\s+|from\s+|@\s*)?"#

    private static func extractTime(from text: inout String, dayparts: [Daypart]) -> (minutes: Int?, ambiguous: String?) {
        if extract(timeLead + #"(?:noon|midday)\b"#, from: &text) != nil {
            return (12 * 60, nil)
        }
        if extract(timeLead + #"midnight\b"#, from: &text) != nil {
            return (0, nil)
        }

        // 5 PM, 5:30pm, 12 a.m.
        if let captures = extract(timeLead + #"(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?![a-z])"#, from: &text),
           let hour = Int(captures[0] ?? ""), (1...12).contains(hour) {
            let minute = Int(captures[1] ?? "0") ?? 0
            guard (0...59).contains(minute) else { return (nil, nil) }
            let isPM = (captures[2] ?? "").lowercased().hasPrefix("p")
            let hour24 = (hour % 12) + (isPM ? 12 : 0)
            return (hour24 * 60 + minute, nil)
        }

        // 17:30, or 5:30 that needs a daypart to resolve.
        if let captures = extract(timeLead + #"(\d{1,2}):(\d{2})\b"#, from: &text),
           let hour = Int(captures[0] ?? ""), let minute = Int(captures[1] ?? ""), hour <= 23, minute <= 59 {
            if hour == 0 || hour >= 13 {
                return (hour * 60 + minute, nil)
            }
            if let resolved = resolve(hour: hour, with: dayparts) {
                return (resolved * 60 + minute, nil)
            }
            return (nil, "at \(hour):\(String(format: "%02d", minute))")
        }

        // "at 5", "5 o'clock", "tomorrow at 17".
        let bare = #"\b(?:at\s+|around\s+|by\s+)(\d{1,2})\b(?!\s*(?::|minutes?|mins?|min\b|hours?|hrs?|days?|weeks?|%|-))"#
        let oclock = #"\b(?:at\s+|around\s+|by\s+)?(\d{1,2})\s*o'?\s*clock\b"#
        if let captures = extract(oclock, from: &text) ?? extract(bare, from: &text),
           let hour = Int(captures[0] ?? ""), hour <= 23 {
            if hour >= 13 {
                return (hour * 60, nil)
            }
            if let resolved = resolve(hour: hour, with: dayparts) {
                return (resolved * 60, nil)
            }
            return (nil, "at \(hour)")
        }

        return (nil, nil)
    }

    private static func resolve(hour: Int, with dayparts: [Daypart]) -> Int? {
        guard let kind = dayparts.first?.kind else { return nil }
        switch kind {
        case .morning:
            return hour == 12 ? 0 : hour
        case .afternoon, .evening:
            return hour < 12 ? hour + 12 : hour
        }
    }

    // MARK: - Date

    private static let monthNames = #"january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"#
    private static let weekdayNames = #"monday|tuesday|wednesday|thursday|friday|saturday|sunday"#
    private static let weekdayAbbreviations = #"mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun"#

    private static func extractDate(from text: inout String, today: Date, calendar: Calendar) -> Date? {
        if let captures = extract(#"\b(?:on\s+)?(20\d{2})-(\d{2})-(\d{2})\b"#, from: &text),
           let year = Int(captures[0] ?? ""), let month = Int(captures[1] ?? ""), let day = Int(captures[2] ?? ""),
           let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
            return calendar.startOfDay(for: date)
        }

        let monthFirst = #"\b(?:on\s+)?("# + monthNames + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?::|a\.?m|p\.?m|o'?clock))"#
        let dayFirst = #"\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + monthNames + #")\b\.?"#
        if let captures = extract(monthFirst, from: &text),
           let month = monthIndex(captures[0]), let day = Int(captures[1] ?? ""),
           let date = upcoming(month: month, day: day, after: today, calendar: calendar) {
            return date
        }
        if let captures = extract(dayFirst, from: &text),
           let day = Int(captures[0] ?? ""), let month = monthIndex(captures[1]),
           let date = upcoming(month: month, day: day, after: today, calendar: calendar) {
            return date
        }

        if extract(#"\b(?:on\s+)?(?:the\s+)?day\s+after\s+tomorrow\b"#, from: &text) != nil {
            return calendar.date(byAdding: .day, value: 2, to: today)
        }
        if extract(#"\btomorrow\b"#, from: &text) != nil {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if extract(#"\b(?:for\s+)?today\b"#, from: &text) != nil {
            return today
        }
        if let captures = extract(#"\bin\s+("# + numberWord + #")\s+(days?|weeks?)\b"#, from: &text),
           let amount = number(from: captures[0]) {
            let unit = (captures[1] ?? "").lowercased()
            let days = Int(amount) * (unit.hasPrefix("week") ? 7 : 1)
            return calendar.date(byAdding: .day, value: days, to: today)
        }

        let fullWeekday = #"\b(next|this|on|coming)?\s*("# + weekdayNames + #")\b"#
        let shortWeekday = #"\b(next|this|on|coming)\s+("# + weekdayAbbreviations + #")\b\.?"#
        if let captures = extract(fullWeekday, from: &text) ?? extract(shortWeekday, from: &text),
           let weekday = weekdayIndex(captures[1]) {
            let modifier = (captures[0] ?? "").lowercased()
            let todayWeekday = calendar.component(.weekday, from: today)
            var ahead = (weekday - todayWeekday + 7) % 7
            if modifier == "next" && ahead == 0 {
                ahead = 7
            }
            return calendar.date(byAdding: .day, value: ahead, to: today)
        }

        return nil
    }

    private static func monthIndex(_ name: String?) -> Int? {
        guard let name = name?.lowercased() else { return nil }
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return prefixes.firstIndex { name.hasPrefix($0) }.map { $0 + 1 }
    }

    private static func weekdayIndex(_ name: String?) -> Int? {
        guard let name = name?.lowercased() else { return nil }
        let prefixes = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return prefixes.firstIndex { name.hasPrefix($0) }.map { $0 + 1 }
    }

    /// The next occurrence of month/day on or after today.
    private static func upcoming(month: Int, day: Int, after today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        if calendar.startOfDay(for: thisYear) >= today {
            return calendar.startOfDay(for: thisYear)
        }
        return calendar.date(from: DateComponents(year: year + 1, month: month, day: day)).map { calendar.startOfDay(for: $0) }
    }

    // MARK: - Regex helpers

    /// Removes the first match of `pattern` from `text` and returns its
    /// capture groups (nil when a group did not participate).
    @discardableResult
    private static func extract(_ pattern: String, from text: inout String) -> [String?]? {
        let regex = try! Regex(pattern).ignoresCase()
        guard let match = text.firstMatch(of: regex) else { return nil }
        var captures: [String?] = []
        for index in 1..<match.output.count {
            captures.append(match.output[index].substring.map(String.init))
        }
        text.replaceSubrange(match.range, with: " ")
        return captures
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        let regex = try! Regex(pattern).ignoresCase()
        return text.replacing(regex, with: replacement)
    }
}
