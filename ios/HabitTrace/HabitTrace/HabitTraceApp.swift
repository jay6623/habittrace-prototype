import SwiftUI

@main
struct HabitTraceApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var taskService = TaskService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(taskService)
        }
    }
}
