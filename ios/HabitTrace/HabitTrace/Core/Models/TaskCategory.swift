import Foundation

/// The fixed category list used by the PWA (`TASK_CATEGORIES`).
///
/// Raw values are the exact strings stored in `task_category`. Legacy
/// values such as "General" normalize to `.other`.
enum TaskCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case study = "Study"
    case work = "Work"
    case chores = "Chores"
    case fitnessHealth = "Fitness/Health"
    case errandsAdmin = "Errands/Admin"
    case hobbiesLeisure = "Hobbies/Leisure"
    case social = "Social"
    case other = "Other"

    var id: String { rawValue }

    /// Maps a stored category to a known case, falling back to `.other`.
    static func normalized(_ raw: String?) -> TaskCategory {
        guard let raw else { return .other }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame } ?? .other
    }
}
