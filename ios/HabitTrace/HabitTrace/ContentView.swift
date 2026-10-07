import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Loading HabitTrace...")
            } else if authManager.isAuthenticated {
                TaskListView()
            } else {
                LoginView()
            }
        }
    }
}
