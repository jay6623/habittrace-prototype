import Foundation

/// A plan request with every field tagged by where its value came from, so
/// the intent can ask only for what is missing, confirm only what was
/// interpreted, and never save a guess silently. Pure value; the intent
/// turns it into prompts and the service turns it into an API call.
nonisolated struct PlanRequest: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// Passed as a structured parameter, or answered to a direct question.
        case explicit
        /// Read out of the free-form sentence.
        case parsed
        /// Guessed from other words (category keywords).
        case inferred
        /// Nothing was said; a standard value was used.
        case defaulted
    }

    var title: String
    var titleSource: Source
    /// Start of the planned day.
    var day: Date
    var daySource: Source
    /// Minutes since midnight. Nil until the user states a time: the current
    /// time is never assumed.
    var startMinutes: Int?
    var startSource: Source?
    /// "tonight", "later", "at 5": a time that still needs pinning down.
    var vagueTime: String?
    var durationMinutes: Int
    var durationSource: Source
    var category: TaskCategory
    var categorySource: Source

    static let durationRange = PlanningPreferences.durationRange

    // MARK: - Questions the intent must ask

    var needsTitle: Bool {
        NaturalLanguagePlanParser.titleLooksUnreliable(title)
    }

    var needsStartTime: Bool {
        startMinutes == nil
    }

    var durationIsValid: Bool {
        Self.durationRange.contains(durationMinutes)
    }

    /// Confirmation is required whenever any field was interpreted rather
    /// than supplied. Fully structured Shortcuts runs skip it so automations
    /// keep working without a prompt.
    var needsConfirmation: Bool {
        [titleSource, daySource, durationSource, categorySource].contains { $0 == .parsed || $0 == .inferred }
            || startSource == .parsed
    }

    /// Planned start on the planned day, once a time is known.
    func start(calendar: Calendar = .current) -> Date? {
        guard let startMinutes else { return nil }
        return calendar.date(byAdding: .minute, value: startMinutes, to: day)
    }

    // MARK: - Applying answers

    mutating func apply(title answer: String) {
        let cleaned = NaturalLanguagePlanParser.cleanTitle(answer)
        title = cleaned.isEmpty ? answer.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        titleSource = .explicit

        // A title answered late can still hint at a category; a stated or
        // structured category is never overridden.
        if categorySource == .defaulted, let guess = NaturalLanguagePlanParser.inferCategory(from: title) {
            category = guess
            categorySource = .inferred
        }
    }

    /// Combines an answered time with the day the sentence already named:
    /// "tomorrow" plus an answer of "5 PM" stays on tomorrow. An answer that
    /// names another day replaces the day.
    mutating func apply(startDate: Date, now: Date, calendar: Calendar = .current) {
        let answeredDay = calendar.startOfDay(for: startDate)
        let components = calendar.dateComponents([.hour, .minute], from: startDate)
        startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        startSource = .explicit
        vagueTime = nil

        let answerIsToday = calendar.isDate(answeredDay, inSameDayAs: now)
        if daySource == .parsed, answerIsToday {
            return
        }
        day = answeredDay
        daySource = .explicit
    }

    mutating func apply(durationMinutes answer: Int) {
        durationMinutes = answer
        durationSource = .explicit
    }

    // MARK: - Spoken text

    /// "What time tonight should “Review my slides” start?"
    var startTimePrompt: String {
        guard let vagueTime else {
            return "What time should “\(title)” start?"
        }
        // "at 5" means the clock value was heard but not AM or PM.
        if vagueTime.hasPrefix("at ") {
            return "What time should “\(title)” start? I heard “\(vagueTime)” but not whether that's AM or PM."
        }
        return "What time \(vagueTime) should “\(title)” start?"
    }

    /// True when the sentence carried something besides a title, so a title
    /// follow-up can say so instead of starting over.
    var hasParsedDetails: Bool {
        startMinutes != nil || vagueTime != nil
            || daySource == .parsed || durationSource == .parsed || categorySource == .parsed
    }

    var titlePrompt: String {
        hasParsedDetails ? "I have the details. What should I call this plan?" : "What would you like to plan?"
    }

    var durationPrompt: String {
        "Plans must be between 5 minutes and 8 hours. How many minutes should “\(title)” take?"
    }

    /// "Add “Study session” today at 5:00 PM for 20 minutes under Study?"
    /// Inferred and defaulted values are called out so the user can object.
    func confirmationText(now: Date, calendar: Calendar = .current) -> String {
        var sentence = "Add “\(title)” \(dayText(now: now, calendar: calendar))"
        if let start = start(calendar: calendar) {
            sentence += " at \(TaskTimeFormatting.displayTime(start))"
        }
        sentence += " for \(TaskTimeFormatting.durationText(minutes: durationMinutes))"
        if category != .other || categorySource == .explicit || categorySource == .parsed {
            sentence += " under \(Self.displayName(for: category))"
        }
        sentence += "?"

        var notes: [String] = []
        if durationSource == .defaulted {
            notes.append("\(TaskTimeFormatting.durationText(minutes: durationMinutes)) is your default length.")
        }
        if categorySource == .inferred {
            notes.append("I guessed the category.")
        }
        if notes.isEmpty {
            return sentence
        }
        return sentence + " " + notes.joined(separator: " ")
    }

    func dayText(now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return "on " + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func displayName(for category: TaskCategory) -> String {
        switch category {
        case .fitnessHealth: "Fitness & Health"
        case .errandsAdmin: "Errands & Admin"
        case .hobbiesLeisure: "Hobbies & Leisure"
        default: category.rawValue
        }
    }
}

/// Merges structured intent parameters with what the parser read from the
/// free-form text. Structured values always win; nothing the user said is
/// overwritten by a default.
nonisolated enum PlanRequestResolver {
    static func resolve(
        utterance: String,
        explicitStart: Date?,
        explicitDuration: Int?,
        explicitCategory: TaskCategory?,
        defaultDuration: Int = PlanningPreferences.default.defaultDuration,
        now: Date,
        calendar: Calendar = .current
    ) -> PlanRequest {
        let parsed = NaturalLanguagePlanParser.parse(utterance, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        let rawTitle = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFreeForm = parsed.recognizedAnyCue
            || parsed.title.caseInsensitiveCompare(rawTitle) != .orderedSame

        // Keyword guesses only apply to free-form sentences. A plain title
        // from a Shortcut keeps the previous behaviour (Other, no prompt).
        var category: TaskCategory = .other
        var categorySource: PlanRequest.Source = .defaulted
        if let parsedCategory = parsed.category {
            switch parsed.categorySource {
            case .stated:
                category = parsedCategory
                categorySource = .parsed
            case .inferred where isFreeForm:
                category = parsedCategory
                categorySource = .inferred
            default:
                break
            }
        }

        var request = PlanRequest(
            title: parsed.title,
            titleSource: isFreeForm ? .parsed : .explicit,
            day: parsed.day ?? today,
            daySource: parsed.day == nil ? .defaulted : .parsed,
            startMinutes: parsed.startMinutes,
            startSource: parsed.startMinutes == nil ? nil : .parsed,
            vagueTime: parsed.vagueTime,
            durationMinutes: parsed.durationMinutes ?? defaultDuration,
            durationSource: parsed.durationMinutes == nil ? .defaulted : .parsed,
            category: category,
            categorySource: categorySource
        )

        if let explicitStart {
            let components = calendar.dateComponents([.hour, .minute], from: explicitStart)
            request.day = calendar.startOfDay(for: explicitStart)
            request.daySource = .explicit
            request.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            request.startSource = .explicit
            request.vagueTime = nil
        }
        if let explicitDuration {
            request.durationMinutes = explicitDuration
            request.durationSource = .explicit
        }
        if let explicitCategory {
            request.category = explicitCategory
            request.categorySource = .explicit
        }
        return request
    }
}
