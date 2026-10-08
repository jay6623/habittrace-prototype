import Foundation

/// The five top-level destinations, mirroring the PWA's bottom tab bar.
///
/// Raw values are stable identifiers so they can be persisted or
/// referenced by system integrations later without renaming cases.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case today
    case plans
    case groups
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .plans: "Plans"
        case .groups: "Groups"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .plans: "calendar"
        case .groups: "person.2"
        case .insights: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}
