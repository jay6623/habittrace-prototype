import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Loading HabitTrace...")
            } else if authManager.isAuthenticated {
                signedInView
            } else {
                LoginView()
            }
        }
    }

    private var signedInView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))

                Text("Signed In")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(authManager.currentUserEmail ?? "HabitTrace User")
                    .foregroundStyle(.secondary)

                Button("Sign Out") {
                    Task {
                        await authManager.signOut()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
