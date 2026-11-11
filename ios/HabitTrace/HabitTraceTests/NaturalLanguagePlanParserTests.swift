import Foundation
import Testing
@testable import HabitTrace

/// Free-form plan requests must come apart into title, day, time, duration,
/// and category, with anything uncertain left for a follow-up question.
struct NaturalLanguagePlanParserTests {
    // Tuesday 10 Nov 2026, 1:07 PM local time.
    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 13, minute: 7))!
    }

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day))!)
    }

    private func parse(_ text: String) -> PlanUtteranceInterpretation {
        NaturalLanguagePlanParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: One-sentence, multi-field requests

    @Test func dictatedLabelsAreSeparatedIntoFields() {
        let result = parse("The title is Siri Voice Test, the start time is 5 PM, duration is 20 minutes, and the category is Study.")
        #expect(result.title == "Siri Voice Test")
        #expect(result.titleWasLabelled)
        #expect(result.startMinutes == 17 * 60)
        #expect(result.durationMinutes == 20)
        #expect(result.category == .study)
        #expect(result.categorySource == .stated)
        #expect(result.day == nil)
        #expect(result.vagueTime == nil)
    }

    @Test func milestoneSentenceProducesTheExpectedDraft() {
        let result = parse("Schedule a 20-minute study session at 5 PM in HabitTrace.")
        #expect(result.title == "Study session")
        #expect(result.startMinutes == 17 * 60)
        #expect(result.durationMinutes == 20)
        #expect(result.category == .study)
        #expect(result.categorySource == .inferred)
        #expect(result.day == nil, "no day was spoken; the resolver defaults it to today")
    }

    @Test func studyAlgorithmsAtFivePMForTwentyMinutes() {
        let result = parse("Study algorithms at 5 PM for 20 minutes.")
        #expect(result.title == "Study algorithms")
        #expect(result.startMinutes == 1020)
        #expect(result.durationMinutes == 20)
        #expect(result.category == .study)
    }

    @Test func workoutTomorrowMorning() {
        let result = parse("Create a workout task tomorrow at 8 AM for 45 minutes.")
        #expect(result.title == "Workout")
        #expect(result.day == day(11, 11))
        #expect(result.startMinutes == 8 * 60)
        #expect(result.durationMinutes == 45)
        #expect(result.category == .fitnessHealth)
    }

    @Test func oneHourMeetingNextMondayHasNoTimeYet() {
        let result = parse("Schedule a one-hour capstone meeting next Monday.")
        #expect(result.title == "Capstone meeting")
        #expect(result.day == day(11, 16))
        #expect(result.durationMinutes == 60)
        #expect(result.startMinutes == nil)
        #expect(result.vagueTime == nil)
        #expect(result.category == .study)
    }

    @Test func tonightIsVagueAndPinsToday() {
        let result = parse("Remind me to review my slides tonight.")
        #expect(result.title == "Review my slides")
        #expect(result.day == day(11, 10))
        #expect(result.startMinutes == nil)
        #expect(result.vagueTime == "tonight")
        #expect(result.category == .work)
    }

    @Test func bareTitleWithAppMentionHasNoCues() {
        let result = parse("Add a study session to HabitTrace.")
        #expect(result.title == "Study session")
        #expect(result.recognizedAnyCue == false)
        #expect(result.category == .study)
        #expect(result.startMinutes == nil)
        #expect(result.durationMinutes == nil)
    }

    // MARK: Times

    // Typed explicitly: twelve untyped tuples with arithmetic time out the
    // type checker.
    private static let preciseTimes: [(String, Int)] = [
        ("Team sync at 17:30", 17 * 60 + 30),
        ("Dentist at 9:15 am", 9 * 60 + 15),
        ("Lunch at noon", 12 * 60),
        ("Backup at midnight", 0),
        ("Feed the cat at 12:30 AM", 30),
        ("Lunch break at 12 PM", 12 * 60),
        ("Gym at 6 in the evening", 18 * 60),
        ("Run at 6 in the morning", 6 * 60),
        ("Call at 5:30 tonight", 17 * 60 + 30),
        ("Standup at 9 o'clock in the morning", 9 * 60),
        ("Dinner at 19", 19 * 60),
        ("Yoga at 7 p.m.", 19 * 60),
    ]

    @Test(arguments: preciseTimes)
    func twelveAndTwentyFourHourTimes(text: String, expected: Int) {
        let result = parse(text)
        #expect(result.startMinutes == expected, "\(text)")
        #expect(result.vagueTime == nil, "\(text)")
    }

    @Test(arguments: [
        ("Call mom at 5", "at 5"),
        ("Call mom at 5:30", "at 5:30"),
        ("Do laundry later", "later"),
        ("Read this evening", "this evening"),
    ])
    func ambiguousTimesAreFlaggedNotGuessed(text: String, hint: String) {
        let result = parse(text)
        #expect(result.startMinutes == nil, "\(text)")
        #expect(result.vagueTime == hint, "\(text)")
    }

    @Test func timeCuesNeverLeakIntoTheTitle() {
        #expect(parse("Gym at 6 in the evening").title == "Gym")
        #expect(parse("Call mom at 5").title == "Call mom")
        #expect(parse("Read this evening").title == "Read")
        #expect(parse("Yoga at 7 p.m.").title == "Yoga")
    }

    // MARK: Durations

    @Test(arguments: [
        ("Nap for an hour", 60),
        ("Deep work for an hour and a half", 90),
        ("Tidy up for half an hour", 30),
        ("Write for 2 hours 15 minutes", 135),
        ("Piano for 90 mins", 90),
        ("Draft for 1.5 hours", 90),
        ("Stretch for forty-five minutes", 45),
        ("Two-hour lab", 120),
        ("Read 25 min", 25),
        ("Review that takes 10 minutes", 10),
    ])
    func durationsInWordsAndNumbers(text: String, expected: Int) {
        #expect(parse(text).durationMinutes == expected, "\(text)")
    }

    @Test func durationWordsAreRemovedFromTheTitle() {
        #expect(parse("Two-hour lab").title == "Lab")
        #expect(parse("Nap for an hour").title == "Nap")
        #expect(parse("Review that takes 10 minutes").title == "Review")
    }

    // MARK: Dates

    @Test(arguments: [
        ("Groceries on Friday", 11, 13),
        ("Groceries Tuesday", 11, 10),
        ("Groceries next Tuesday", 11, 17),
        ("Groceries in 3 days", 11, 13),
        ("Groceries in a week", 11, 17),
        ("Groceries on Nov 20", 11, 20),
        ("Groceries December 1st", 12, 1),
        ("Groceries on the 3rd of December", 12, 3),
        ("Groceries on 2026-12-05", 12, 5),
        ("Groceries the day after tomorrow", 11, 12),
        ("Groceries today", 11, 10),
    ])
    func relativeAndAbsoluteDates(text: String, month: Int, dayOfMonth: Int) {
        let result = parse(text)
        #expect(result.day == day(month, dayOfMonth), "\(text)")
        #expect(result.title == "Groceries", "\(text)")
    }

    @Test func pastCalendarDatesRollToNextYear() {
        #expect(parse("Taxes on March 1").day == day(3, 1, year: 2027))
    }

    @Test func theWordMayIsNotAMonthWithoutADay() {
        let result = parse("I may study at 5 PM")
        #expect(result.day == nil)
        #expect(result.startMinutes == 17 * 60)
    }

    // MARK: Categories

    @Test(arguments: [
        ("Finish the deck under Work", TaskCategory.work),
        ("Swim, category is fitness and health", .fitnessHealth),
        ("Board games in the social category", .social),
        ("Renew passport, category: Errands", .errandsAdmin),
        ("Sketching filed under hobbies", .hobbiesLeisure),
    ])
    func statedCategoriesAreRecognized(text: String, expected: TaskCategory) {
        let result = parse(text)
        #expect(result.category == expected, "\(text)")
        #expect(result.categorySource == .stated, "\(text)")
    }

    @Test(arguments: [
        ("Work out", TaskCategory.fitnessHealth),
        ("Pay bills", .errandsAdmin),
        ("Fold the laundry", .chores),
        ("Practice guitar", .hobbiesLeisure),
        ("Dinner with Sam", .social),
        ("Client meeting", .work),
        ("Read chapter 4", .study),
    ])
    func categoriesAreInferredFromKeywords(text: String, expected: TaskCategory) {
        let result = parse(text)
        #expect(result.category == expected, "\(text)")
        #expect(result.categorySource == .inferred, "\(text)")
    }

    @Test func unknownTitlesHaveNoCategory() {
        let result = parse("Thing at 3 PM")
        #expect(result.category == nil)
        #expect(result.categorySource == nil)
    }

    // MARK: Title clean-up

    @Test(arguments: [
        ("Please add a plan called Grocery run at 3 PM", "Grocery run"),
        ("I need to pay bills tomorrow at 10am", "Pay bills"),
        ("Can you schedule a dentist appointment on Friday at 2 PM", "Dentist appointment"),
        ("New task: write the lab report tonight", "Write the lab report"),
        ("Block out time to read tomorrow at 9 PM", "Time to read"),
        ("Study session.", "Study session"),
    ])
    func commandsAndFillerAreStripped(text: String, expected: String) {
        #expect(parse(text).title == expected, "\(text)")
    }

    @Test func sentencesWithOnlyCuesLeaveAnUnreliableTitle() {
        let result = parse("5 PM for 20 minutes tomorrow")
        #expect(result.title.isEmpty)
        #expect(result.titleLooksUnreliable)
        #expect(result.startMinutes == 17 * 60)
        #expect(result.durationMinutes == 20)
    }

    @Test func leftoverSchedulingWordsMakeATitleUnreliable() {
        #expect(NaturalLanguagePlanParser.titleLooksUnreliable("duration is twenty and the category is study"))
        #expect(NaturalLanguagePlanParser.titleLooksUnreliable("   "))
        #expect(NaturalLanguagePlanParser.titleLooksUnreliable(String(repeating: "a", count: 201)))
        #expect(NaturalLanguagePlanParser.titleLooksUnreliable("Study session") == false)
    }
}

/// Structured parameters, parsed fields, defaults, and follow-up answers
/// must combine without ever overwriting something the user said.
struct PlanRequestResolverTests {
    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 13, minute: 7))!
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func resolve(
        _ utterance: String,
        start: Date? = nil,
        duration: Int? = nil,
        category: TaskCategory? = nil
    ) -> PlanRequest {
        PlanRequestResolver.resolve(
            utterance: utterance,
            explicitStart: start,
            explicitDuration: duration,
            explicitCategory: category,
            now: now,
            calendar: calendar
        )
    }

    @Test func freeFormSentenceBecomesAConfirmedDraft() {
        let request = resolve("Schedule a 20-minute study session at 5 PM in HabitTrace.")
        #expect(request.title == "Study session")
        #expect(request.day == calendar.startOfDay(for: now))
        #expect(request.daySource == .defaulted)
        #expect(request.start(calendar: calendar) == date(11, 10, 17, 0))
        #expect(request.startSource == .parsed)
        #expect(request.durationMinutes == 20)
        #expect(request.category == .study)
        #expect(request.categorySource == .inferred)
        #expect(request.needsTitle == false)
        #expect(request.needsStartTime == false)
        #expect(request.needsConfirmation)
    }

    @Test func noTimeIsNeverReplacedByTheCurrentTime() {
        let request = resolve("Add a study session to HabitTrace.")
        #expect(request.needsStartTime)
        #expect(request.start(calendar: calendar) == nil)
        #expect(request.startTimePrompt == "What time should “Study session” start?")
    }

    @Test func vagueTimesAskWithTheHint() {
        let request = resolve("Remind me to review my slides tonight.")
        #expect(request.needsStartTime)
        #expect(request.startTimePrompt == "What time tonight should “Review my slides” start?")
    }

    @Test func explicitParametersBeatParsedAndInferredValues() {
        let request = resolve(
            "Study algorithms at 5 PM for 20 minutes",
            start: date(11, 12, 9, 30),
            duration: 50,
            category: .work
        )
        #expect(request.start(calendar: calendar) == date(11, 12, 9, 30))
        #expect(request.startSource == .explicit)
        #expect(request.daySource == .explicit)
        #expect(request.durationMinutes == 50)
        #expect(request.durationSource == .explicit)
        #expect(request.category == .work)
        #expect(request.categorySource == .explicit)
    }

    @Test func fullyStructuredShortcutRunsSkipConfirmation() {
        let request = resolve("Write report", start: date(11, 10, 14, 0), duration: 30, category: .work)
        #expect(request.titleSource == .explicit)
        #expect(request.needsConfirmation == false)
        #expect(request.needsTitle == false)
    }

    @Test func plainTitleWithStructuredTimeStillGetsDefaultDurationWithoutConfirmation() {
        let request = resolve("Write report", start: date(11, 10, 14, 0))
        #expect(request.durationMinutes == 30)
        #expect(request.durationSource == .defaulted)
        #expect(request.needsConfirmation == false)
    }

    @Test func answeredTimeKeepsTheSpokenDay() {
        var request = resolve("Schedule a one-hour capstone meeting next Monday.")
        #expect(request.needsStartTime)
        request.apply(startDate: date(11, 10, 15, 0), now: now, calendar: calendar)
        #expect(request.start(calendar: calendar) == date(11, 16, 15, 0), "the answer named only a time, so Monday stays")
        #expect(request.startSource == .explicit)
        #expect(request.vagueTime == nil)
    }

    @Test func answeredDateOnAnotherDayReplacesTheDay() {
        var request = resolve("Groceries tomorrow")
        request.apply(startDate: date(11, 20, 10, 0), now: now, calendar: calendar)
        #expect(request.day == calendar.startOfDay(for: date(11, 20)))
        #expect(request.daySource == .explicit)
        #expect(request.startMinutes == 600)
    }

    @Test func unreliableTitlesAreAskedForAndCleaned() {
        var request = resolve("5 PM for 20 minutes tomorrow")
        #expect(request.needsTitle)
        request.apply(title: "a study session")
        #expect(request.title == "Study session")
        #expect(request.titleSource == .explicit)
        #expect(request.needsTitle == false)
        #expect(request.durationMinutes == 20, "fields parsed earlier survive the follow-up")
        #expect(request.startMinutes == 17 * 60)
    }

    @Test func outOfRangeDurationsAreCaughtBeforeSaving() {
        var request = resolve("Nap for 2 minutes at 3 PM")
        #expect(request.durationIsValid == false)
        request.apply(durationMinutes: 20)
        #expect(request.durationIsValid)
        #expect(request.durationSource == .explicit)
    }

    @Test func confirmationTextNamesEveryInterpretedField() {
        let today = resolve("Schedule a 20-minute study session at 5 PM")
        let time = TaskTimeFormatting.displayTime(date(11, 10, 17, 0))
        #expect(today.confirmationText(now: now, calendar: calendar) == "Add “Study session” today at \(time) for 20 min under Study? I guessed the category.")

        let tomorrow = resolve("Create a workout tomorrow at 8 AM for 45 minutes", category: .fitnessHealth)
        let eight = TaskTimeFormatting.displayTime(date(11, 11, 8, 0))
        #expect(tomorrow.confirmationText(now: now, calendar: calendar) == "Add “Workout” tomorrow at \(eight) for 45 min under Fitness & Health?")

        let defaulted = resolve("Call the bank on Friday at 10 AM")
        let ten = TaskTimeFormatting.displayTime(date(11, 13, 10, 0))
        let friday = date(11, 13).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        #expect(defaulted.confirmationText(now: now, calendar: calendar) == "Add “Call the bank” on \(friday) at \(ten) for 30 min under Errands & Admin? 30 min is your default length. I guessed the category.")
    }

    @Test func confirmationOmitsOtherCategoryWhenNothingWasSaid() {
        let request = resolve("Thing at 3 PM for 15 minutes")
        #expect(request.confirmationText(now: now, calendar: calendar).contains("under") == false)
    }
}
