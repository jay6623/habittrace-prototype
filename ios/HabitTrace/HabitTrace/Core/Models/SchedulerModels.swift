import Foundation

// Contracts for the Scheduler feature ("Find a time" and "Generate day").
// Mirrors `lib/api.ts` in the PWA and the backend's `ai_prediction.py`,
// `ai_time_recommendation.py`, and `daily_schedule.py` schemas.
//
// `DailySchedule`, `DailyScheduledTask`, and `DailyUnscheduledTask` live in
// `CoachModels.swift` and are reused here; `DailyScheduleMeta` decodes the
// extra response fields the scheduler needs from the same JSON.

// MARK: - Errors

/// Client-side failures raised by the scheduler flows.
nonisolated enum SchedulerError: LocalizedError, Equatable, Sendable {
    /// The server accepted the sync request but has not linked an AI plan
    /// input yet. Mirrors the PWA's `"AI plan sync is pending."`.
    case aiPlanPending
    /// A date/time could not be turned into a timestamp.
    case invalidTime

    var errorDescription: String? {
        switch self {
        case .aiPlanPending: "AI plan sync is pending."
        case .invalidTime: "That time could not be used."
        }
    }
}

// MARK: - AI plan resolution

/// The PWA's `ensureAIPlan` decision: reuse the linked plan input id or ask
/// the server to sync one.
nonisolated enum AIPlanResolution: Equatable, Sendable {
    case ready(planID: String)
    case needsSync

    /// `.ready` when the task already carries an `ai_plan_input_id`.
    static func resolve(planInputID: String?) -> AIPlanResolution {
        if let planInputID, !planInputID.isEmpty {
            return .ready(planID: planInputID)
        }
        return .needsSync
    }

    /// Validates the task returned by `POST /tasks/{id}/ai-plan`; a missing
    /// id means the sync is still pending.
    static func planID(fromSyncedPlanInputID planInputID: String?) throws -> String {
        guard let planInputID, !planInputID.isEmpty else {
            throw SchedulerError.aiPlanPending
        }
        return planInputID
    }
}

// MARK: - Predictions

/// One history-derived signal in `personalization.factors`.
nonisolated struct AIPersonalizationFactor: Codable, Equatable, Sendable {
    var type: String
    var direction: String
    var sampleCount: Int
    var message: String

    init(type: String, direction: String, sampleCount: Int, message: String) {
        self.type = type
        self.direction = direction
        self.sampleCount = sampleCount
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? ""
        direction = (try? container.decodeIfPresent(String.self, forKey: .direction)) ?? ""
        sampleCount = (try? container.decodeIfPresent(Int.self, forKey: .sampleCount)) ?? 0
        message = (try? container.decodeIfPresent(String.self, forKey: .message)) ?? ""
    }
}

/// The PWA's `PersonalizationSummary`. The backend sends a free-form
/// dictionary, so every field decodes leniently.
nonisolated struct AIPersonalization: Codable, Equatable, Sendable {
    var applied: Bool
    var sampleCount: Int
    var confidence: Double
    var historySuccessRate: Double?
    var factors: [AIPersonalizationFactor]

    init(
        applied: Bool,
        sampleCount: Int,
        confidence: Double = 0,
        historySuccessRate: Double? = nil,
        factors: [AIPersonalizationFactor] = []
    ) {
        self.applied = applied
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.historySuccessRate = historySuccessRate
        self.factors = factors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applied = (try? container.decodeIfPresent(Bool.self, forKey: .applied)) ?? false
        sampleCount = (try? container.decodeIfPresent(Int.self, forKey: .sampleCount)) ?? 0
        confidence = (try? container.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0
        historySuccessRate = try? container.decodeIfPresent(Double.self, forKey: .historySuccessRate)
        factors = (try? container.decodeIfPresent([AIPersonalizationFactor].self, forKey: .factors)) ?? []
    }
}

/// A practical suggestion attached to a prediction.
nonisolated struct AIRecommendedAction: Codable, Equatable, Sendable, Identifiable {
    var code: String
    var title: String
    var detail: String

    var id: String { code }

    init(code: String, title: String, detail: String) {
        self.code = code
        self.title = title
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? UUID().uuidString
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        detail = (try? container.decodeIfPresent(String.self, forKey: .detail)) ?? ""
    }
}

/// `AIPredictResponse`: the persisted V2 prediction for one plan input.
/// `explanation` is intentionally not modelled.
nonisolated struct AIPredictResponse: Codable, Equatable, Sendable {
    var modelVersion: String
    var successProbability: Double
    var baseSuccessProbability: Double?
    var personalization: AIPersonalization?
    var failureReasonProbabilities: [String: Double]
    var predictedFailureReason: String?
    var predictedAt: String
    var recommendedActions: [AIRecommendedAction]

    init(
        modelVersion: String,
        successProbability: Double,
        baseSuccessProbability: Double? = nil,
        personalization: AIPersonalization? = nil,
        failureReasonProbabilities: [String: Double] = [:],
        predictedFailureReason: String? = nil,
        predictedAt: String = "",
        recommendedActions: [AIRecommendedAction] = []
    ) {
        self.modelVersion = modelVersion
        self.successProbability = successProbability
        self.baseSuccessProbability = baseSuccessProbability
        self.personalization = personalization
        self.failureReasonProbabilities = failureReasonProbabilities
        self.predictedFailureReason = predictedFailureReason
        self.predictedAt = predictedAt
        self.recommendedActions = recommendedActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelVersion = (try? container.decodeIfPresent(String.self, forKey: .modelVersion)) ?? ""
        successProbability = try container.decode(Double.self, forKey: .successProbability)
        baseSuccessProbability = try? container.decodeIfPresent(Double.self, forKey: .baseSuccessProbability)
        personalization = try? container.decodeIfPresent(AIPersonalization.self, forKey: .personalization)
        failureReasonProbabilities = (try? container.decodeIfPresent([String: Double].self, forKey: .failureReasonProbabilities)) ?? [:]
        predictedFailureReason = try? container.decodeIfPresent(String.self, forKey: .predictedFailureReason)
        predictedAt = (try? container.decodeIfPresent(String.self, forKey: .predictedAt)) ?? ""
        recommendedActions = (try? container.decodeIfPresent([AIRecommendedAction].self, forKey: .recommendedActions)) ?? []
    }

    /// Whole-number percentage clamped to 0...100, as the PWA displays it.
    var successPercent: Int {
        Self.percent(successProbability)
    }

    /// `Math.round(clamp(value, 0, 1) * 100)`.
    static func percent(_ probability: Double) -> Int {
        Int((min(max(probability, 0), 1) * 100).rounded())
    }
}

/// `GET /api/v2/ai/plans/{id}/prediction` wraps the row as `{"prediction": …}`.
nonisolated struct AIPredictionEnvelope: Decodable, Sendable {
    var prediction: AIPredictResponse?
}

// MARK: - Time recommendations

/// `POST /api/v2/ai/plans/{id}/time-recommendations` body.
nonisolated struct TimeRecommendationRequest: Codable, Equatable, Sendable {
    var earliestStart: String
    var latestEnd: String
    var slotIntervalMinutes: Int = 15
    var minimumBufferMinutes: Int = 15
}

/// `POST /api/v2/ai/time-recommendations/{id}/select` body.
nonisolated struct TimeCandidateSelection: Codable, Equatable, Sendable {
    var candidateId: String
    var status: String = "accepted"
}

/// One ranked start time.
nonisolated struct TimeCandidate: Codable, Equatable, Sendable, Identifiable {
    /// `reason_snapshot`: free-form, so decoded leniently.
    nonisolated struct ReasonSnapshot: Codable, Equatable, Sendable {
        var predictedFailureReason: String?
        var strategy: String?
        var personalization: AIPersonalization?

        init(predictedFailureReason: String? = nil, strategy: String? = nil, personalization: AIPersonalization? = nil) {
            self.predictedFailureReason = predictedFailureReason
            self.strategy = strategy
            self.personalization = personalization
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            predictedFailureReason = try? container.decodeIfPresent(String.self, forKey: .predictedFailureReason)
            strategy = try? container.decodeIfPresent(String.self, forKey: .strategy)
            personalization = try? container.decodeIfPresent(AIPersonalization.self, forKey: .personalization)
        }
    }

    var id: String
    var recommendationId: String?
    var candidateStart: String
    var candidateEnd: String
    var predictedSuccessProbability: Double
    var rank: Int
    var reasonSnapshot: ReasonSnapshot?

    init(
        id: String,
        recommendationId: String? = nil,
        candidateStart: String,
        candidateEnd: String,
        predictedSuccessProbability: Double,
        rank: Int,
        reasonSnapshot: ReasonSnapshot? = nil
    ) {
        self.id = id
        self.recommendationId = recommendationId
        self.candidateStart = candidateStart
        self.candidateEnd = candidateEnd
        self.predictedSuccessProbability = predictedSuccessProbability
        self.rank = rank
        self.reasonSnapshot = reasonSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        recommendationId = try? container.decodeIfPresent(String.self, forKey: .recommendationId)
        candidateStart = try container.decode(String.self, forKey: .candidateStart)
        candidateEnd = try container.decode(String.self, forKey: .candidateEnd)
        predictedSuccessProbability = (try? container.decodeIfPresent(Double.self, forKey: .predictedSuccessProbability)) ?? 0
        rank = (try? container.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        reasonSnapshot = try? container.decodeIfPresent(ReasonSnapshot.self, forKey: .reasonSnapshot)
    }

    var successPercent: Int {
        AIPredictResponse.percent(predictedSuccessProbability)
    }
}

/// `TimeRecommendationResponse`.
nonisolated struct TimeRecommendation: Codable, Equatable, Sendable {
    var id: String
    var planInputId: String?
    var status: String?
    var selectedCandidateId: String?
    var slotIntervalMinutes: Int?
    var minimumBufferMinutes: Int?
    var candidates: [TimeCandidate]

    init(
        id: String,
        planInputId: String? = nil,
        status: String? = nil,
        selectedCandidateId: String? = nil,
        slotIntervalMinutes: Int? = nil,
        minimumBufferMinutes: Int? = nil,
        candidates: [TimeCandidate]
    ) {
        self.id = id
        self.planInputId = planInputId
        self.status = status
        self.selectedCandidateId = selectedCandidateId
        self.slotIntervalMinutes = slotIntervalMinutes
        self.minimumBufferMinutes = minimumBufferMinutes
        self.candidates = candidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        planInputId = try? container.decodeIfPresent(String.self, forKey: .planInputId)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        selectedCandidateId = try? container.decodeIfPresent(String.self, forKey: .selectedCandidateId)
        slotIntervalMinutes = try? container.decodeIfPresent(Int.self, forKey: .slotIntervalMinutes)
        minimumBufferMinutes = try? container.decodeIfPresent(Int.self, forKey: .minimumBufferMinutes)
        candidates = (try? container.decodeIfPresent([TimeCandidate].self, forKey: .candidates)) ?? []
    }

    /// Candidates in rank order.
    var rankedCandidates: [TimeCandidate] {
        candidates.sorted { $0.rank < $1.rank }
    }
}

// MARK: - Daily schedules

/// `POST /tasks/{id}/ai-plan` body.
nonisolated struct TaskAISyncRequest: Codable, Equatable, Sendable {
    var timezoneName: String
}

/// One `DailyScheduleTaskInput`. Optional timestamps encode as explicit
/// `null`, as the PWA sends them.
nonisolated struct DailyScheduleTaskRequest: Codable, Equatable, Sendable {
    var clientId: String
    var title: String
    var estimatedDurationMinutes: Int
    var deadlineAt: String?
    var importance: Int
    var category: String
    var difficulty: Int
    var requiredEnergy: Int
    var requiredFocus: Int
    var isFixedTime: Bool
    var fixedStart: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientId, forKey: .clientId)
        try container.encode(title, forKey: .title)
        try container.encode(estimatedDurationMinutes, forKey: .estimatedDurationMinutes)
        try container.encode(deadlineAt, forKey: .deadlineAt)
        try container.encode(importance, forKey: .importance)
        try container.encode(category, forKey: .category)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(requiredEnergy, forKey: .requiredEnergy)
        try container.encode(requiredFocus, forKey: .requiredFocus)
        try container.encode(isFixedTime, forKey: .isFixedTime)
        try container.encode(fixedStart, forKey: .fixedStart)
    }
}

/// `POST /api/v2/ai/daily-schedules/generate` body.
nonisolated struct DailyScheduleGenerateRequest: Codable, Equatable, Sendable {
    var selectedDate: String
    var timezoneName: String
    var dayStart: String
    var dayEnd: String
    var minimumBufferMinutes: Int = 15
    var slotIntervalMinutes: Int = 15
    var maxPlannedMinutes: Int = 480
    var maxFocusBlockMinutes: Int = 120
    var tasks: [DailyScheduleTaskRequest]
}

/// One `PATCH /api/v2/ai/daily-schedules/{id}` adjustment.
nonisolated struct DailyScheduleAdjustment: Codable, Equatable, Sendable {
    var taskId: String
    var scheduledStart: String
}

/// `PATCH /api/v2/ai/daily-schedules/{id}` body.
nonisolated struct DailyScheduleUpdateRequest: Codable, Equatable, Sendable {
    var adjustments: [DailyScheduleAdjustment]
}

/// Response fields the scheduler needs that `DailySchedule` (shared with
/// the coach) does not carry. Decoded from the same JSON.
nonisolated struct DailyScheduleMeta: Codable, Equatable, Sendable {
    nonisolated struct TaskMeta: Codable, Equatable, Sendable {
        var taskId: String
        var importance: Int?
        var isFixedTime: Bool?
        var planInputId: String?
    }

    var dayStart: String?
    var dayEnd: String?
    var minimumBufferMinutes: Int?
    var slotIntervalMinutes: Int?
    var confirmedAt: String?
    var scheduledTasks: [TaskMeta]

    init(
        dayStart: String? = nil,
        dayEnd: String? = nil,
        minimumBufferMinutes: Int? = nil,
        slotIntervalMinutes: Int? = nil,
        confirmedAt: String? = nil,
        scheduledTasks: [TaskMeta] = []
    ) {
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.minimumBufferMinutes = minimumBufferMinutes
        self.slotIntervalMinutes = slotIntervalMinutes
        self.confirmedAt = confirmedAt
        self.scheduledTasks = scheduledTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayStart = try? container.decodeIfPresent(String.self, forKey: .dayStart)
        dayEnd = try? container.decodeIfPresent(String.self, forKey: .dayEnd)
        minimumBufferMinutes = try? container.decodeIfPresent(Int.self, forKey: .minimumBufferMinutes)
        slotIntervalMinutes = try? container.decodeIfPresent(Int.self, forKey: .slotIntervalMinutes)
        confirmedAt = try? container.decodeIfPresent(String.self, forKey: .confirmedAt)
        scheduledTasks = (try? container.decodeIfPresent([TaskMeta].self, forKey: .scheduledTasks)) ?? []
    }

    func importance(for taskID: String) -> Int? {
        scheduledTasks.first { $0.taskId == taskID }?.importance
    }

    func isFixedTime(_ taskID: String) -> Bool {
        scheduledTasks.first { $0.taskId == taskID }?.isFixedTime ?? false
    }
}

/// A `DailyScheduleResponse` split into the shared `DailySchedule` and the
/// scheduler-only metadata.
nonisolated struct GeneratedDaySchedule: Equatable, Sendable {
    var schedule: DailySchedule
    var meta: DailyScheduleMeta

    init(schedule: DailySchedule, meta: DailyScheduleMeta) {
        self.schedule = schedule
        self.meta = meta
    }

    /// Decodes both halves from one response body.
    init(data: Data, decoder: JSONDecoder) throws {
        schedule = try decoder.decode(DailySchedule.self, from: data)
        meta = (try? decoder.decode(DailyScheduleMeta.self, from: data)) ?? DailyScheduleMeta()
    }

    var isDraft: Bool { schedule.status == "draft" }
    var bufferMinutes: Int { meta.minimumBufferMinutes ?? 15 }
    var slotIntervalMinutes: Int { meta.slotIntervalMinutes ?? 15 }
}
