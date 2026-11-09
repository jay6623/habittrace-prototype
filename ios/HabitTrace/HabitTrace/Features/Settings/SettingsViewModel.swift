import Foundation
import Combine

/// State for the Settings tab: profile and planning preference edits,
/// avatar changes, the records export, and sign-out. Copy follows the
/// PWA's `/dashboard/settings`.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var name: String
    @Published var preferences: PlanningPreferences
    @Published private(set) var isBusy = false
    @Published private(set) var isAvatarBusy = false
    @Published private(set) var isSigningOut = false
    @Published var errorMessage: String?
    @Published var toast: HTToastMessage?
    /// Temporary file to hand to the share sheet after an export.
    @Published var exportFileURL: URL?

    private let authManager: AuthManager
    private let apiClient: APIClient

    init(authManager: AuthManager, apiClient: APIClient = APIClient()) {
        self.authManager = authManager
        self.apiClient = apiClient
        name = authManager.displayName == "there" ? "" : authManager.displayName
        preferences = authManager.planningPreferences
    }

    /// Re-seeds the form from the current session, e.g. after a save.
    func reloadFromSession() {
        name = authManager.displayName == "there" ? "" : authManager.displayName
        preferences = authManager.planningPreferences
    }

    var email: String { authManager.currentUserEmail ?? "" }
    var initials: String { authManager.avatarInitials }
    var avatarURL: URL? { authManager.avatarURL }
    var hasCustomAvatar: Bool { authManager.hasCustomAvatar }
    var timeZoneName: String { TimeZone.current.identifier }

    // MARK: - Save

    func save() async {
        guard !isBusy else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Enter a display name."
            return
        }
        if let validation = preferences.validationError {
            errorMessage = validation
            return
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await authManager.saveProfile(displayName: trimmed, preferences: preferences)
            reloadFromSession()
            toast = .success("Settings saved. Your name and planning preferences are updated.")
        } catch {
            errorMessage = "Couldn’t save your settings. Your changes are still here."
        }
    }

    // MARK: - Export

    /// Downloads the server export and appends the profile block the PWA
    /// adds client-side, then writes `habittrace-YYYY-MM-DD.json`.
    func exportRecords() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let token = try await authManager.validAccessToken()
            let data = try await apiClient.exportAccount(accessToken: token)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.invalidResponse
            }
            object["profile"] = [
                "name": authManager.displayName,
                "email": email,
                "preferences": [
                    "defaultDuration": preferences.defaultDuration,
                    "workStart": preferences.workStart,
                    "workEnd": preferences.workEnd,
                ],
            ] as [String: Any]

            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            let fileName = "habittrace-\(TaskTimeFormatting.isoDate(from: .now)).json"
            let url = FileManager.default.temporaryDirectory.appending(path: fileName)
            try pretty.write(to: url, options: .atomic)
            exportFileURL = url
            toast = .success("Export ready. Includes your saved plans and execution records.")
        } catch {
            toast = .error("Export failed. No incomplete export was saved. Please try again.")
        }
    }

    // MARK: - Avatar

    func uploadAvatar(imageData: Data) async {
        guard !isAvatarBusy else { return }
        isAvatarBusy = true
        defer { isAvatarBusy = false }

        do {
            try await authManager.uploadAvatar(imageData: imageData)
            toast = .success("Profile picture updated")
        } catch {
            toast = .error("Upload failed. \(ErrorPresentation.message(for: error))")
        }
    }

    func resetAvatar() async {
        guard !isAvatarBusy else { return }
        isAvatarBusy = true
        defer { isAvatarBusy = false }

        do {
            try await authManager.clearAvatar()
            toast = .success("Profile picture reset. Using your default avatar again.")
        } catch {
            toast = .error("Couldn’t reset picture. Please try again.")
        }
    }

    // MARK: - Sign out

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        await authManager.signOut()
        if authManager.errorMessage != nil {
            toast = .error("Couldn’t sign out")
            isSigningOut = false
        }
    }
}
