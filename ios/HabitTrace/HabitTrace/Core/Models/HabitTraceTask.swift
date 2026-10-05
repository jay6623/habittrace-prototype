import Foundation

struct HabitTraceTask: Decodable, Identifiable {
    let id: String
    let title: String

    let notes: String?
    let taskCategory: String?

    let plannedDate: String?
    let plannedStartTime: String?
    let plannedDurationMin: Int?

    let importance: Int?
    let energyLevel: Int?
    let focusLevel: Int?

    let taskStatus: String?
    let createdAt: String?
}
