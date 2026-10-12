import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Loading HabitTrace...")
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        // The shared service outlives sign-in and sign-out. Clear it whenever
        // the account changes so one user's data never appears under another.
        .onChange(of: authManager.currentUserID) { previous, current in
            if previous != current {
                taskService.reset()
            }
        }
    }
}
