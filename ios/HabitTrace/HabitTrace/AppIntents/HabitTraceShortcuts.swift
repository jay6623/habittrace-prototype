import AppIntents

/// App Shortcuts make the intents available to Siri and Spotlight without
/// setup. Phrases are a spoken contract: add new ones, don't rename.
nonisolated struct HabitTraceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetTodaysPlansIntent(),
            phrases: [
                "What's on my \(.applicationName) plan today",
                "Show my \(.applicationName) plans for today",
                "What do I have planned in \(.applicationName)",
                "Get today's plans from \(.applicationName)",
            ],
            shortTitle: "Today's Plans",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: AddPlanIntent(),
            phrases: [
                "Add a plan in \(.applicationName)",
                "Plan something in \(.applicationName)",
                "Create a \(.applicationName) plan",
                "New \(.applicationName) plan",
                "Schedule something in \(.applicationName)",
                "Add a task to \(.applicationName)",
                "Schedule a plan in \(.applicationName)",
            ],
            shortTitle: "Add a Plan",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: PlanWithHabitTraceIntent(),
            phrases: [
                "Plan with \(.applicationName)",
                "Tell \(.applicationName) my plan",
                "Dictate a plan to \(.applicationName)",
            ],
            shortTitle: "Plan with HabitTrace",
            systemImageName: "mic.badge.plus"
        )
    }
}
