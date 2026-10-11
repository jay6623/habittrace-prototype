import Foundation
import Supabase

extension AuthManager {
    /// Short name for greetings: the `first_name` the PWA stores in
    /// Supabase user metadata, else the local part of the email.
    var greetingName: String? {
        if
            let firstName = session?.user.userMetadata["first_name"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !firstName.isEmpty
        {
            return firstName
        }

        if
            let email = currentUserEmail,
            let localPart = email.split(separator: "@").first,
            !localPart.isEmpty
        {
            return String(localPart)
        }

        return nil
    }

    /// The PWA's saved default plan length, from
    /// `user_metadata.planning_preferences.defaultDuration`, when valid.
    var defaultPlanDurationMinutes: Int? {
        guard
            let preferences = session?.user.userMetadata["planning_preferences"]?.objectValue,
            let raw = preferences["defaultDuration"]
        else {
            return nil
        }

        let minutes: Int?
        if let integer = raw.intValue {
            minutes = integer
        } else if let double = raw.doubleValue {
            minutes = Int(double)
        } else {
            minutes = nil
        }

        guard let minutes, PlanDraft.durationRange.contains(minutes) else {
            return nil
        }
        return minutes
    }
}
