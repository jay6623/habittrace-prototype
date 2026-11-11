import Foundation

extension APIClient {
    // MARK: - AI plan linkage

    /// `POST /tasks/{id}/ai-plan`: asks the server to (re)deliver the plan
    /// snapshot and returns the task, whose `aiPlanInputId` is set once the
    /// sync succeeded. 409 for tasks with outcomes; 503 while pending.
    func createAIPlan(
        accessToken: String,
        taskID: String,
        timezoneName: String = TimeZone.current.identifier
    ) async throws -> HabitTraceTask {
        let request = try makeRequest(
            .post,
            path: "tasks/\(taskID)/ai-plan",
            body: TaskAISyncRequest(timezoneName: timezoneName),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// The PWA's `ensureAIPlan`: returns the linked plan input id, syncing
    /// one when the task has none. Throws `SchedulerError.aiPlanPending`
    /// when the server still reports no id.
    func ensureAIPlan(
        accessToken: String,
        task: HabitTraceTask,
        timezoneName: String = TimeZone.current.identifier
    ) async throws -> String {
        if case .ready(let planID) = AIPlanResolution.resolve(planInputID: task.aiPlanInputId) {
            return planID
        }
        let synced = try await createAIPlan(
            accessToken: accessToken,
            taskID: task.id,
            timezoneName: task.timezoneName ?? timezoneName
        )
        return try AIPlanResolution.planID(fromSyncedPlanInputID: synced.aiPlanInputId)
    }

    // MARK: - Predictions

    /// `GET /api/v2/ai/plans/{id}/prediction`: the latest persisted
    /// prediction, or nil when the plan has none (`{"prediction": null}`
    /// or 404).
    func fetchAIPlanPrediction(accessToken: String, planInputID: String) async throws -> AIPredictResponse? {
        let request = try makeRequest(.get, path: "api/v2/ai/plans/\(planInputID)/prediction", accessToken: accessToken)
        do {
            let data = try await perform(request)
            if data.isEmpty || String(decoding: data, as: UTF8.self) == "null" {
                return nil
            }
            return try makeDecoder().decode(AIPredictionEnvelope.self, from: data).prediction
        } catch APIError.httpStatus(404, _) {
            return nil
        } catch let error as DecodingError {
            throw APIError.decoding(error)
        }
    }

    /// `POST /api/v2/ai/plans/{id}/predict`: creates and persists a
    /// prediction for the plan.
    func predictAIPlan(accessToken: String, planInputID: String) async throws -> AIPredictResponse {
        var request = try makeRequest(.post, path: "api/v2/ai/plans/\(planInputID)/predict", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    /// The PWA's `getOrCreateAIPlanPrediction`: reuse the persisted
    /// prediction and create one only when the plan has none.
    func getOrCreateAIPlanPrediction(accessToken: String, planInputID: String) async throws -> AIPredictResponse {
        if let existing = try await fetchAIPlanPrediction(accessToken: accessToken, planInputID: planInputID) {
            return existing
        }
        return try await predictAIPlan(accessToken: accessToken, planInputID: planInputID)
    }

    // MARK: - Time recommendations

    /// `POST /api/v2/ai/plans/{id}/time-recommendations`.
    func createTimeRecommendation(
        accessToken: String,
        planInputID: String,
        request body: TimeRecommendationRequest
    ) async throws -> TimeRecommendation {
        let request = try makeRequest(
            .post,
            path: "api/v2/ai/plans/\(planInputID)/time-recommendations",
            body: body,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /api/v2/ai/time-recommendations/{id}/select` with
    /// `status: "accepted"`.
    func selectTimeCandidate(
        accessToken: String,
        recommendationID: String,
        candidateID: String
    ) async throws -> TimeRecommendation {
        let request = try makeRequest(
            .post,
            path: "api/v2/ai/time-recommendations/\(recommendationID)/select",
            body: TimeCandidateSelection(candidateId: candidateID),
            accessToken: accessToken
        )
        return try await send(request)
    }

    // MARK: - Daily schedules

    /// `POST /api/v2/ai/daily-schedules/generate` → a draft schedule.
    func generateDailySchedule(
        accessToken: String,
        request body: DailyScheduleGenerateRequest
    ) async throws -> GeneratedDaySchedule {
        let request = try makeRequest(.post, path: "api/v2/ai/daily-schedules/generate", body: body, accessToken: accessToken)
        return try await sendDailySchedule(request)
    }

    /// `GET /api/v2/ai/daily-schedules/{id}`.
    func fetchDailySchedule(accessToken: String, scheduleID: String) async throws -> GeneratedDaySchedule {
        let request = try makeRequest(.get, path: "api/v2/ai/daily-schedules/\(scheduleID)", accessToken: accessToken)
        return try await sendDailySchedule(request)
    }

    /// `PATCH /api/v2/ai/daily-schedules/{id}` with start-time adjustments.
    func updateDailySchedule(
        accessToken: String,
        scheduleID: String,
        adjustments: [DailyScheduleAdjustment]
    ) async throws -> GeneratedDaySchedule {
        let request = try makeRequest(
            .patch,
            path: "api/v2/ai/daily-schedules/\(scheduleID)",
            body: DailyScheduleUpdateRequest(adjustments: adjustments),
            accessToken: accessToken
        )
        return try await sendDailySchedule(request)
    }

    /// Decodes a `DailyScheduleResponse` into the shared schedule plus the
    /// scheduler-only metadata. `confirmDailySchedule` (in `APIClient+Chat`)
    /// returns only the shared half.
    private func sendDailySchedule(_ request: URLRequest) async throws -> GeneratedDaySchedule {
        let data = try await perform(request)
        do {
            return try GeneratedDaySchedule(data: data, decoder: makeDecoder())
        } catch {
            throw APIError.decoding(error)
        }
    }
}
