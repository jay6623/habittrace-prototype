import Foundation
import Supabase
import AuthenticationServices

/// Account flows beyond email sign-in: sign-up, Google OAuth, password
/// reset, profile and preference updates, avatars, and Google Calendar
/// authorization. All calls go through the shared Supabase client; the
/// session published by `AuthManager` updates via its auth-state stream.
extension AuthManager {
    /// Custom scheme registered in the target's Info.plist. Both URLs must
    /// be allow-listed under Authentication → URL Configuration in the
    /// Supabase project for OAuth and password-reset links to return here.
    nonisolated static let authCallbackURL = URL(string: "habittrace://auth-callback")!
    nonisolated static let passwordResetURL = URL(string: "habittrace://reset-password")!

    enum AccountError: LocalizedError {
        case notSignedIn
        case calendarAccountMismatch
        case calendarAccessMissing
        case imageTooLarge
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "You need to sign in."
            case .calendarAccountMismatch:
                "That Google account belongs to a different HabitTrace user. Sign in again and choose the Google account that matches this one."
            case .calendarAccessMissing:
                "Google did not return Calendar access. Please connect again and approve Calendar permission."
            case .imageTooLarge:
                "That image is still too large after compression. Try another photo."
            case .invalidImage:
                "Choose an image file."
            }
        }
    }

    enum DeepLinkResult {
        case signedIn
        case passwordRecovery
    }

    private var client: SupabaseClient { SupabaseProvider.client }

    // MARK: - Profile values

    /// The PWA's `displayName`: `first_name`, else the email's local part,
    /// else "there".
    var displayName: String {
        if let name = session?.user.userMetadata["first_name"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = currentUserEmail, let local = email.split(separator: "@").first, !local.isEmpty {
            return String(local)
        }
        return "there"
    }

    var planningPreferences: PlanningPreferences {
        PlanningPreferences(metadata: session?.user.userMetadata ?? [:])
    }

    /// Custom upload first, then the Google profile picture.
    var avatarURL: URL? {
        let metadata = session?.user.userMetadata ?? [:]
        for key in ["avatar_url", "picture"] {
            if let value = metadata[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty, let url = URL(string: value) {
                return url
            }
        }
        return nil
    }

    var hasCustomAvatar: Bool {
        let value = session?.user.userMetadata["avatar_url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(value ?? "").isEmpty
    }

    /// Up to two initials from the display name, else the email.
    var avatarInitials: String {
        let source = displayName == "there" ? (currentUserEmail ?? "?") : displayName
        let parts = source.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return String([first, second]).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    // MARK: - Sign-up and OAuth

    /// `supabase.auth.signUp` with the PWA's metadata keys. Returns true
    /// when the project requires email confirmation (no session yet).
    func signUp(email: String, password: String, firstName: String, lastName: String) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "first_name": .string(firstName),
                "last_name": .string(lastName),
            ],
            redirectTo: Self.authCallbackURL
        )
        return response.session == nil
    }

    /// Google sign-in through the system web auth session
    /// (`ASWebAuthenticationSession`, PKCE). Always shows the account
    /// chooser, as the PWA does.
    ///
    /// Supabase only redirects to `authCallbackURL` when that exact URL is
    /// allow-listed in the project's Redirect URLs. Otherwise it falls back
    /// to the Site URL (the PWA), the sheet never receives the `habittrace`
    /// scheme, and this call waits until the user dismisses the sheet.
    func signInWithGoogle() async throws {
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: Self.authCallbackURL,
            queryParams: [(name: "prompt", value: "select_account")]
        )
        adopt(session: session)
    }

    /// Completes OAuth or password-recovery links opened from Mail or Safari.
    func handleDeepLink(_ url: URL) async throws -> DeepLinkResult {
        let session = try await client.auth.session(from: url)
        adopt(session: session)
        return Self.isPasswordRecoveryLink(url) ? .passwordRecovery : .signedIn
    }

    /// True for links that should open the password-reset form instead of
    /// landing on the dashboard.
    nonisolated static func isPasswordRecoveryLink(_ url: URL) -> Bool {
        url.host() == Self.passwordResetURL.host()
            || url.absoluteString.contains("type=recovery")
    }

    // MARK: - Password

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.passwordResetURL)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    // MARK: - Profile & preferences

    /// Saves the display name and planning preferences to user metadata,
    /// then mirrors the name into the public `profiles` row used by Groups.
    func saveProfile(displayName: String, preferences: PlanningPreferences) async throws {
        guard let userID = currentUserID else { throw AccountError.notSignedIn }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        _ = try await client.auth.update(user: UserAttributes(data: [
            "first_name": .string(name),
            "planning_preferences": preferences.metadataValue,
        ]))
        try await client.from("profiles")
            .upsert(ProfileRow(id: userID, displayName: name), onConflict: "id")
            .execute()
        _ = try await validAccessToken()
    }

    // MARK: - Avatar

    /// Resizes to 256px, uploads to the `avatars` bucket, and falls back to
    /// an inline data URL when the bucket is unavailable, as the PWA does.
    func uploadAvatar(imageData: Data) async throws {
        guard let userID = currentUserID else { throw AccountError.notSignedIn }
        let jpeg = try AvatarImage.compressedJPEG(from: imageData)
        let path = "\(userID)/avatar.jpg"

        var avatarURL: String
        do {
            _ = try await client.storage.from("avatars")
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
            avatarURL = "\(publicURL.absoluteString)?v=\(Int(Date.now.timeIntervalSince1970))"
        } catch {
            let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            guard dataURL.count <= AvatarImage.maxDataURLLength else { throw AccountError.imageTooLarge }
            avatarURL = dataURL
        }

        _ = try await client.auth.update(user: UserAttributes(data: ["avatar_url": .string(avatarURL)]))
        try await client.from("profiles")
            .upsert(ProfileAvatarRow(id: userID, avatarUrl: avatarURL), onConflict: "id")
            .execute()
        _ = try await validAccessToken()
    }

    /// Clears the custom picture so the Google photo or initials show again.
    func clearAvatar() async throws {
        guard let userID = currentUserID else { throw AccountError.notSignedIn }
        _ = try? await client.storage.from("avatars").remove(paths: ["\(userID)/avatar.jpg"])
        _ = try await client.auth.update(user: UserAttributes(data: ["avatar_url": .string("")]))
        _ = try await validAccessToken()
        let fallback = avatarURL?.absoluteString
        try await client.from("profiles")
            .upsert(ProfileAvatarRow(id: userID, avatarUrl: fallback), onConflict: "id")
            .execute()
    }

    // MARK: - Google Calendar authorization

    struct GoogleCalendarGrant {
        let providerToken: String
        let providerRefreshToken: String?
    }

    /// Runs the calendar-scoped Google flow. Because Supabase treats this as
    /// a sign-in, the returned session is checked against the user who
    /// started it; a different Google account is dropped locally so nobody
    /// silently continues as someone else.
    func authorizeGoogleCalendar() async throws -> GoogleCalendarGrant {
        guard let expectedUserID = currentUserID else { throw AccountError.notSignedIn }
        var params: [(name: String, value: String?)] = [
            (name: "access_type", value: "offline"),
            (name: "prompt", value: "consent"),
            (name: "include_granted_scopes", value: "true"),
        ]
        if let email = currentUserEmail {
            params.append((name: "login_hint", value: email))
        }

        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: Self.authCallbackURL,
            scopes: "https://www.googleapis.com/auth/calendar.events",
            queryParams: params
        )

        guard session.user.id.uuidString == expectedUserID else {
            try? await client.auth.signOut(scope: .local)
            throw AccountError.calendarAccountMismatch
        }
        guard let token = session.providerToken, !token.isEmpty else {
            throw AccountError.calendarAccessMissing
        }
        return GoogleCalendarGrant(providerToken: token, providerRefreshToken: session.providerRefreshToken)
    }

    /// True when the user dismissed the system sign-in sheet.
    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}

private struct ProfileRow: Encodable {
    let id: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct ProfileAvatarRow: Encodable {
    let id: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case avatarUrl = "avatar_url"
    }
}
