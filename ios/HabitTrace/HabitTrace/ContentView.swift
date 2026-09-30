import SwiftUI

struct ContentView: View {
    @State private var health: HealthResponse?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 56))

                Text("HabitTrace")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if isLoading {
                    ProgressView()

                    Text("Connecting to backend...")
                        .foregroundStyle(.secondary)

                } else if let health {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))

                    Text("Backend Connected")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Status: \(health.status)")
                        .foregroundStyle(.secondary)

                    Text(
                        health.ready
                            ? "Backend is fully ready."
                            : "Backend is running, but some services are not configured."
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 42))

                    Text("Connection Failed")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(errorMessage ?? "Unknown error")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .task {
                await loadHealth()
            }
        }
    }

    @MainActor
    private func loadHealth() async {
        isLoading = true
        errorMessage = nil

        do {
            health = try await APIClient().fetchHealth()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    ContentView()
}
