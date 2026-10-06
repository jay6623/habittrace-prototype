import Foundation

struct HabitTraceExecution: Codable, Identifiable {
    let id: String
    let taskId: String
    let userId: String
    let actualStartTime: String
    let actualEndTime: String?
    let interruptionCount: Int
    let stoppedEarly: Bool
    let taskStatus: String?
    let failureReason: String?
    let createdAt: String
}
