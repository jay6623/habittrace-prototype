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
}
