import SwiftUI

/// Six-tab shell shown to authenticated users.
struct MainTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: .today) {
                TodayView(onViewPlans: { selectedTab = .plans })
            }

            Tab(AppTab.plans.title, systemImage: AppTab.plans.systemImage, value: .plans) {
                PlansView()
            }

            Tab(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage, value: .calendar) {
                CalendarView()
            }

            Tab(AppTab.groups.title, systemImage: AppTab.groups.systemImage, value: .groups) {
                GroupsView()
            }

            Tab(AppTab.insights.title, systemImage: AppTab.insights.systemImage, value: .insights) {
                InsightsView(onPlanSomething: { selectedTab = .plans })
            }

            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
                SettingsView()
            }
        }
        .tint(HTColor.brand)
    }
}
