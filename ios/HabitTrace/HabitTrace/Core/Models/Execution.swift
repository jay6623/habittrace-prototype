import Foundation

/// An execution record, matching the backend's `ExecutionResponse`.
///
/// Active executions have a start time but no end time and no task status.
/// `not_started` outcomes have neither time. `completion_ratio` is a Decimal
/// on the server and may be serialized as a JSON string, so it is decoded
/// tolerantly.
struct HabitTraceExecution: Codable, Identifiable, Equatable {
    let id: String
    let taskId: String
    let userId: String
    let actualStartTime: String?
    let actualEndTime: String?
    let interruptionCount: Int
    let stoppedEarly: Bool
    /// "success", "failed", or nil while the execution is still active.
    let taskStatus: String?
    let failureReason: String?
    let outcomeStatus: OutcomeStatus?
    let completionRatio: Double?
    let activeMinutes: Int?
    let aiOutcomeSyncStatus: String?
    let createdAt: String

    /// True while the execution has been started but not finished.
    var isActive: Bool {
        actualEndTime == nil && taskStatus == nil
    }

    var failureReasonCode: FailureReason? {
        failureReason.flatMap(FailureReason.init(rawValue:))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case taskId
        case userId
        case actualStartTime
        case actualEndTime
        case interruptionCount
        case stoppedEarly
        case taskStatus
        case failureReason
        case outcomeStatus
        case completionRatio
        case activeMinutes
        case aiOutcomeSyncStatus
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        taskId = try container.decode(String.self, forKey: .taskId)
        userId = try container.decode(String.self, forKey: .userId)
        actualStartTime = try container.decodeIfPresent(String.self, forKey: .actualStartTime)
        actualEndTime = try container.decodeIfPresent(String.self, forKey: .actualEndTime)
        interruptionCount = try container.decodeIfPresent(Int.self, forKey: .interruptionCount) ?? 0
        stoppedEarly = try container.decodeIfPresent(Bool.self, forKey: .stoppedEarly) ?? false
        taskStatus = try container.decodeIfPresent(String.self, forKey: .taskStatus)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        activeMinutes = try container.decodeIfPresent(Int.self, forKey: .activeMinutes)
        aiOutcomeSyncStatus = try container.decodeIfPresent(String.self, forKey: .aiOutcomeSyncStatus)
        createdAt = try container.decode(String.self, forKey: .createdAt)

        // Unknown future outcome values decode as nil rather than failing the record.
        let rawOutcome = try container.decodeIfPresent(String.self, forKey: .outcomeStatus)
        outcomeStatus = rawOutcome.flatMap(OutcomeStatus.init(rawValue:))

        // Decimal may arrive as a number or as a string such as "0.50000".
        if let number = try? container.decodeIfPresent(Double.self, forKey: .completionRatio) {
            completionRatio = number
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .completionRatio) {
            completionRatio = Double(text)
        } else {
            completionRatio = nil
        }
    }

    init(
        id: String,
        taskId: String,
        userId: String,
        actualStartTime: String?,
        actualEndTime: String?,
        interruptionCount: Int,
        stoppedEarly: Bool,
        taskStatus: String?,
        failureReason: String?,
        outcomeStatus: OutcomeStatus? = nil,
        completionRatio: Double? = nil,
        activeMinutes: Int? = nil,
        aiOutcomeSyncStatus: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.taskId = taskId
        self.userId = userId
        self.actualStartTime = actualStartTime
        self.actualEndTime = actualEndTime
        self.interruptionCount = interruptionCount
        self.stoppedEarly = stoppedEarly
        self.taskStatus = taskStatus
        self.failureReason = failureReason
        self.outcomeStatus = outcomeStatus
        self.completionRatio = completionRatio
        self.activeMinutes = activeMinutes
        self.aiOutcomeSyncStatus = aiOutcomeSyncStatus
        self.createdAt = createdAt
    }
}
