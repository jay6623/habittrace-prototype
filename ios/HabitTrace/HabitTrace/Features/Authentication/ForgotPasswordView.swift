import SwiftUI

/// "Reset password": sends Supabase's recovery email. Mirrors `/forgot-password`.
struct ForgotPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HTSpacing.lg) {
                HStack(spacing: HTSpacing.md) {
                    AuthLogo(size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset password")
                            .htSectionTitle()
                        Text("Get a secure link by email")
                            .font(.htBody)
                            .foregroundStyle(HTColor.textMuted)
                    }
                }

                if let errorMessage {
                    AuthNotice(text: errorMessage, tone: .error)
                }
                if let message {
                    AuthNotice(text: message, tone: .success)
                }

                AuthField(label: "Email") {
                    TextField("paul@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                }

                Button(isLoading ? "Sending..." : "Send reset email") {
                    Task { await send() }
                }
                .buttonStyle(.htPrimary(fullWidth: true))
                .disabled(isLoading)

                HStack(spacing: HTSpacing.xs) {
                    Text("Remembered it?")
                        .foregroundStyle(HTColor.textMuted)
                    Button("Back to login") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(HTColor.textPrimary)
                }
                .font(.htBody)
                .frame(maxWidth: .infinity)
            }
            .padding(HTSpacing.xxl)
            .htPanel()
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.vertical, HTSpacing.lg)
        }
        .background(HTColor.surfaceMuted)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your email address."
            return
        }

        isLoading = true
        errorMessage = nil
        message = nil
        defer { isLoading = false }

        do {
            try await authManager.sendPasswordReset(email: trimmed)
            message = "Password reset email sent. Check your inbox and follow the link."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// "Create new password", shown after a recovery link opens the app.
/// Mirrors `/reset-password`.
struct ResetPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    HStack(spacing: HTSpacing.md) {
                        AuthLogo(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create new password")
                                .htSectionTitle()
                            Text("Use a password reset link from your email")
                                .font(.htBody)
                                .foregroundStyle(HTColor.textMuted)
                        }
                    }

                    if let errorMessage {
                        AuthNotice(text: errorMessage, tone: .error)
                    }
                    if let message {
                        AuthNotice(text: message, tone: .success)
                    }
                    if !authManager.isAuthenticated {
                        AuthNotice(
                            text: "This reset link is missing or expired. Request a new password reset email.",
                            tone: .warning
                        )
                    }

                    AuthField(label: "New password") {
                        SecureField("Enter new password", text: $password)
                            .textContentType(.newPassword)
                    }
                    AuthField(label: "Confirm password") {
                        SecureField("Confirm new password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }

                    Button(isLoading ? "Saving..." : "Update password") {
                        Task { await update() }
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(isLoading || !authManager.isAuthenticated)
                }
                .padding(HTSpacing.xxl)
                .htPanel()
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.vertical, HTSpacing.lg)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func update() async {
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

        isLoading = true
        errorMessage = nil
        message = nil
        defer { isLoading = false }

        do {
            try await authManager.updatePassword(password)
            message = "Password updated. You can now log in with your new password."
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
