import SwiftUI

/// Root of the signed-out flow: sign in, with routes to sign-up and
/// password reset. Copy mirrors the PWA's `/login`.
struct AuthFlowView: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var isGoogleBusy = false
    @State private var localError: String?

    private var isBusy: Bool { authManager.isLoading || isGoogleBusy }

    var body: some View {
        ScrollView {
            VStack(spacing: HTSpacing.xl) {
                VStack(spacing: HTSpacing.md) {
                    AuthLogo()
                    Text("Welcome back")
                        .htPageTitle()
                    Text("Sign in to plan, start, and finish your day.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                        .multilineTextAlignment(.center)
                }

                if let message = localError ?? authManager.errorMessage {
                    AuthNotice(text: message, tone: .error)
                }

                GoogleButton(title: "Continue with Google", isBusy: isBusy) {
                    Task { await signInWithGoogle() }
                }

                AuthDivider(text: "OR USE EMAIL")

                VStack(spacing: HTSpacing.lg) {
                    AuthField(label: "Email") {
                        TextField("you@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                    }

                    VStack(alignment: .leading, spacing: HTSpacing.sm) {
                        HStack {
                            Text("Password")
                                .font(.htBodyStrong)
                                .foregroundStyle(HTColor.textStrong)
                            Spacer()
                            NavigationLink("Forgot password?") {
                                ForgotPasswordView()
                            }
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textMuted)
                        }
                        SecureField("Enter your password", text: $password)
                            .textContentType(.password)
                            .htField()
                            .submitLabel(.go)
                            .onSubmit { Task { await signIn() } }
                    }

                    Button(authManager.isLoading ? "Signing in…" : "Sign in with email") {
                        Task { await signIn() }
                    }
                    .buttonStyle(.htSecondary(minHeight: HTControlHeight.prominent, fullWidth: true))
                    .disabled(isBusy)
                }

                HStack(spacing: HTSpacing.xs) {
                    Text("New to HabitTrace?")
                        .foregroundStyle(HTColor.textMuted)
                    NavigationLink("Create an account") {
                        SignUpView()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(HTColor.textPrimary)
                }
                .font(.htBody)
            }
            .padding(HTSpacing.xxl)
            .htPanel()
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.vertical, HTSpacing.xxl)
        }
        .background(HTColor.surfaceMuted)
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func signIn() async {
        localError = nil
        guard !email.isEmpty, !password.isEmpty else {
            localError = "Please enter your email and password."
            return
        }
        await authManager.signIn(email: email, password: password)
    }

    private func signInWithGoogle() async {
        guard !isGoogleBusy else { return }
        isGoogleBusy = true
        localError = nil
        authManager.errorMessage = nil
        defer { isGoogleBusy = false }

        do {
            try await authManager.signInWithGoogle()
        } catch where AuthManager.isUserCancellation(error) {
            // Dismissed the Google sheet.
        } catch {
            localError = error.localizedDescription
        }
    }
}

#Preview {
    AuthFlowView()
        .environmentObject(AuthManager())
}
