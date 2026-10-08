import SwiftUI

/// Settings tab. Shows the signed-in account and hosts Sign Out,
/// which moved here from the task list to match the PWA.
struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Email") {
                        Text(authManager.currentUserEmail ?? "—")
                            .foregroundStyle(HTColor.textMuted)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        Text("Sign out")
                            .frame(maxWidth: .infinity)
                    }
                }

                if let errorMessage = authManager.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.htCaption)
                            .foregroundStyle(HTColor.danger700)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HTColor.surfaceMuted)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Sign out of HabitTrace?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await authManager.signOut()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
