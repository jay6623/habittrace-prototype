import SwiftUI

/// "Password & security": set a new password while signed in, or send
/// the PWA's reset-link email to the signed-in address.
struct PasswordSecurityView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var isSendingEmail = false
    @State private var errorMessage: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HTSpacing.lg) {
                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    Text("Create new password")
                        .htSectionTitle()

                    if let errorMessage {
                        AuthNotice(text: errorMessage, tone: .error)
                    }
                    if let message {
                        AuthNotice(text: message, tone: .success)
                    }

                    AuthField(label: "New password") {
                        SecureField("Enter new password", text: $password)
                            .textContentType(.newPassword)
                    }
                    AuthField(label: "Confirm password") {
                        SecureField("Confirm new password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }

                    Button(isSaving ? "Saving..." : "Update password") {
                        Task { await updatePassword() }
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(isSaving)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .htPanel()

                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    Text("Reset by email")
                        .htSectionTitle()
                    Text("Get a secure link at \(authManager.currentUserEmail ?? "your email"). Open it on this device to choose a new password.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                    Button(isSendingEmail ? "Sending..." : "Send reset email") {
                        Task { await sendResetEmail() }
                    }
                    .buttonStyle(.htSecondary(fullWidth: true))
                    .disabled(isSendingEmail || authManager.currentUserEmail == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .htPanel()
            }
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.vertical, HTSpacing.lg)
        }
        .background(HTColor.surfaceMuted)
        .navigationTitle("Password & security")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updatePassword() async {
        if password.isEmpty || confirmPassword.isEmpty {
            errorMessage = "Please enter and confirm your new password."
            return
        }
        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        if password != confirmPassword {
            errorMessage = "Passwords do not match."
            return
        }

        isSaving = true
        errorMessage = nil
        message = nil
        defer { isSaving = false }

        do {
            try await authManager.updatePassword(password)
            password = ""
            confirmPassword = ""
            message = "Password updated. You can now log in with your new password."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendResetEmail() async {
        guard let email = authManager.currentUserEmail else { return }
        isSendingEmail = true
        errorMessage = nil
        message = nil
        defer { isSendingEmail = false }

        do {
            try await authManager.sendPasswordReset(email: email)
            message = "Password reset email sent. Check your inbox and follow the link."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
