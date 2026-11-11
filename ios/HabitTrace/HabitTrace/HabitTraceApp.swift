import AppIntents
import SwiftUI

@main
struct HabitTraceApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var taskService: TaskService

    init() {
        let service = TaskService()
        _taskService = StateObject(wrappedValue: service)

        // App Intents can run as soon as the process launches, so the
        // shared task service is registered before any scene appears.
        AppDependencyManager.shared.add(dependency: service)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(taskService)
        }
    }
}
