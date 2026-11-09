import CoreGraphics
import Foundation
import Supabase
import Testing
@testable import HabitTrace

/// `planning_preferences` parsing and validation, mirroring `lib/preferences.ts`.
struct PlanningPreferencesTests {
    @Test func missingMetadataUsesDefaults() {
        let preferences = PlanningPreferences(metadata: [:])
        #expect(preferences == .default)
        #expect(preferences.defaultDuration == 30)
        #expect(preferences.workStart == "09:00")
        #expect(preferences.workEnd == "22:00")
    }

    @Test func validValuesAreKept() {
        let preferences = PlanningPreferences(metadata: [
            "planning_preferences": .object([
                "defaultDuration": .integer(45),
                "workStart": .string("07:30"),
                "workEnd": .string("18:00"),
            ]),
        ])
        #expect(preferences.defaultDuration == 45)
        #expect(preferences.workStart == "07:30")
        #expect(preferences.workEnd == "18:00")
    }

    @Test func invalidValuesFallBackIndividually() {
        let preferences = PlanningPreferences(metadata: [
            "planning_preferences": .object([
                "defaultDuration": .integer(4),
                "workStart": .string("7:30"),
                "workEnd": .string("25:00"),
            ]),
        ])
        #expect(preferences == .default)

        let doubleDuration = PlanningPreferences(metadata: [
            "planning_preferences": .object(["defaultDuration": .double(60)]),
        ])
        #expect(doubleDuration.defaultDuration == 60)
    }

    @Test func metadataRoundTrips() {
        let original = PlanningPreferences(defaultDuration: 25, workStart: "08:00", workEnd: "20:15")
        let parsed = PlanningPreferences(metadata: ["planning_preferences": original.metadataValue])
        #expect(parsed == original)
    }

    @Test func validationMatchesPWA() {
        var preferences = PlanningPreferences.default
        #expect(preferences.validationError == nil)

        preferences.workEnd = "09:00"
        #expect(preferences.validationError == "Daily availability must end after it starts.")

        preferences = .default
        preferences.defaultDuration = 500
        #expect(preferences.validationError == "Default plan duration must be between 5 and 480 minutes.")
    }

    @Test func timeHelpersRoundTrip() {
        #expect(PlanningPreferences.minutes(from: "09:05") == 545)
        #expect(PlanningPreferences.time(fromMinutes: 545) == "09:05")
        #expect(PlanningPreferences.time(fromMinutes: 24 * 60 + 10) == "23:59")
        #expect(PlanningPreferences.validTime("23:59") == "23:59")
        #expect(PlanningPreferences.validTime("24:00") == nil)
        #expect(PlanningPreferences.validTime(nil) == nil)
    }

    @Test func googleMarkPathsParse() {
        let paths = [
            "M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z",
            "M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z",
            "M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z",
            "M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z",
        ]
        for data in paths {
            let path = CGPath.fromSVG(data)
            #expect(path != nil)
            #expect(path?.isEmpty == false)
        }
        #expect(CGPath.fromSVG("M 1 2 Q 3") == nil)
    }
}
