import SwiftUI

/// Scheduler entry: a segmented switch between "Find a time" and
/// "Generate day", mirroring the PWA's plan tabs without "List".
///
/// Navigation-container free: present it in a sheet or push it onto a
/// `NavigationStack`, with `AuthManager` and `TaskService` in the
/// environment. Both tabs stay alive so form state survives switching.
struct SchedulerHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case findTime = "Find a time"
        case generateDay = "Generate day"

        var id: String { rawValue }
    }

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService
    @State private var tab: Tab

    let initialDate: Date
    let initialTaskID: String?

    init(initialTab: Tab = .findTime, initialDate: Date = .now, initialTaskID: String? = nil) {
        _tab = State(initialValue: initialTab)
        self.initialDate = initialDate
        self.initialTaskID = initialTaskID
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scheduler", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.vertical, HTSpacing.sm)
            .background(HTColor.surfaceMuted)

            ZStack {
                FindTimeView(initialDate: initialDate, initialTaskID: initialTaskID)
                    .opacity(tab == .findTime ? 1 : 0)
                    .allowsHitTesting(tab == .findTime)
                    .accessibilityHidden(tab != .findTime)
                GenerateDayView(initialDate: initialDate)
                    .opacity(tab == .generateDay ? 1 : 0)
                    .allowsHitTesting(tab == .generateDay)
                    .accessibilityHidden(tab != .generateDay)
            }
        }
        .background(HTColor.surfaceMuted)
    }
}
