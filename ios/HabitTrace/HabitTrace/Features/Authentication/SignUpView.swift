import SwiftUI

/// "Create your account", mirroring the PWA's `/signup`.
struct SignUpView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreed = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?

    var body: some View {
        ScrollView {
            if let confirmationMessage {
                VStack(spacing: HTSpacing.lg) {
                    Text("Check your inbox")
                        .htPageTitle()
                    Text(confirmationMessage)
                        .font(.htBody)
                        .foregroundStyle(HTColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Go to Login") {
                        dismiss()
                    }
                    .buttonStyle(.htPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(HTSpacing.xxl)
                .htPanel()
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.vertical, HTSpacing.xxl)
            } else {
                form
            }
        }
        .background(HTColor.surfaceMuted)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: HTSpacing.lg) {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text("Create your account")
                    .htPageTitle()
                Text("New users sign up here before moving to the productivity profile setup.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
            }

            if let errorMessage {
                AuthNotice(text: errorMessage, tone: .error)
            }

            GoogleButton(title: "Sign up with Google", isBusy: isLoading) {
                Task { await signUpWithGoogle() }
            }

            AuthDivider(text: "or use email")

            AuthField(label: "First name") {
                TextField("Paul", text: $firstName)
                    .textContentType(.givenName)
            }
            AuthField(label: "Last name") {
                TextField("Cha", text: $lastName)
                    .textContentType(.familyName)
            }
            AuthField(label: "Email") {
                TextField("paul@example.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }
            AuthField(label: "Password") {
                SecureField("Create password", text: $password)
                    .textContentType(.newPassword)
            }
            AuthField(label: "Confirm password") {
                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }

            Toggle(isOn: $agreed) {
                Text("I agree to the Terms of Service and Privacy Policy.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(HTColor.brand)

            Button(isLoading ? "Creating account…" : "Create Account with Email") {
                Task { await signUp() }
            }
            .buttonStyle(.htSecondary(minHeight: HTControlHeight.prominent, fullWidth: true))
            .disabled(isLoading)

            HStack(spacing: HTSpacing.xs) {
                Text("Already have an account?")
                    .foregroundStyle(HTColor.textMuted)
                Button("Log in") {
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

    private func signUp() async {
        if firstName.isEmpty || email.isEmpty || password.isEmpty {
            errorMessage = "Please fill in all required fields."
            return
        }
        if password != confirmPassword {
            errorMessage = "Passwords do not match."
            return
        }
        if !agreed {
            errorMessage = "Please agree to the Terms of Service."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let needsConfirmation = try await authManager.signUp(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            if needsConfirmation {
                confirmationMessage = "Account created! Check your email to confirm, then log in."
            }
            // Otherwise the session stream signs the user in.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signUpWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.signInWithGoogle()
        } catch where AuthManager.isUserCancellation(error) {
            // Dismissed the Google sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
