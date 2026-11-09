import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    @State private var showingPasswordReset = false

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Loading HabitTrace...")
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                AuthFlowView()
            }
        }
        // The shared service outlives sign-in and sign-out. Clear it whenever
        // the account changes so one user's data never appears under another.
        .onChange(of: authManager.currentUserID) { previous, current in
            if previous != current {
                taskService.reset()
            }
        }
        // OAuth and password-recovery links return through the app's URL
        // scheme; Supabase exchanges them for a session here.
        .onOpenURL { url in
            Task {
                await handle(url)
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            ResetPasswordView()
        }
    }

    private func handle(_ url: URL) async {
        do {
            if try await authManager.handleDeepLink(url) == .passwordRecovery {
                showingPasswordReset = true
            }
        } catch {
            authManager.errorMessage = error.localizedDescription
        }
    }
}
