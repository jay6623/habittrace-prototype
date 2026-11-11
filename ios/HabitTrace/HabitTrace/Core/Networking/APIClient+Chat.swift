import Foundation

extension APIClient {
    /// `POST /chat`: streams coach events until `[DONE]`. Each `data:` line
    /// may carry a token, the conversation id, a chart, or a proposal.
    func streamChat(
        accessToken: String,
        message: String,
        history: [ChatHistoryMessage],
        conversationID: String?,
        timezoneName: String = TimeZone.current.identifier
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = ChatRequestBody(
                        message: message,
                        history: history,
                        conversationId: conversationID,
                        timezoneName: timezoneName
                    )
                    var request = try makeRequest(.post, path: "chat", body: body, accessToken: accessToken)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 120

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }
                    guard 200..<300 ~= http.statusCode else {
                        var collected = Data()
                        for try await byte in bytes { collected.append(byte) }
                        throw APIError.httpStatus(http.statusCode, detail: Self.errorDetail(in: collected))
                    }

                    let decoder = makeDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try ChatStreamParser.events(fromLine: line, decoder: decoder) {
                            continuation.yield(event)
                            if case .done = event {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `GET /chat/conversations/latest`; `null` when persistence is off.
    func fetchLatestConversation(accessToken: String) async throws -> CoachConversation? {
        let request = try makeRequest(.get, path: "chat/conversations/latest", accessToken: accessToken)
        let data = try await perform(request)
        if data.isEmpty || String(decoding: data, as: UTF8.self) == "null" {
            return nil
        }
        return try makeDecoder().decode(CoachConversation.self, from: data)
    }

    /// `DELETE /chat/conversations/{id}`.
    func archiveConversation(accessToken: String, conversationID: String) async throws {
        let request = try makeRequest(.delete, path: "chat/conversations/\(conversationID)", accessToken: accessToken)
        _ = try await perform(request)
    }

    /// `POST /chat/proposals/{id}/confirm` → the created task.
    func confirmProposal(
        accessToken: String,
        proposalID: String,
        candidateStart: String?,
        task: CoachTaskDraft
    ) async throws -> HabitTraceTask {
        let request = try makeRequest(
            .post,
            path: "chat/proposals/\(proposalID)/confirm",
            body: ProposalConfirmBody(candidateStart: candidateStart, task: task),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /chat/proposals/{id}/dismiss`.
    func dismissProposal(accessToken: String, proposalID: String) async throws {
        var request = try makeRequest(.post, path: "chat/proposals/\(proposalID)/dismiss", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request)
    }

    /// `POST /api/v2/ai/daily-schedules/{id}/confirm`.
    func confirmDailySchedule(accessToken: String, scheduleID: String) async throws -> DailySchedule {
        var request = try makeRequest(.post, path: "api/v2/ai/daily-schedules/\(scheduleID)/confirm", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private struct ChatRequestBody: Encodable {
        let message: String
        let history: [ChatHistoryMessage]
        let conversationId: String?
        let timezoneName: String
    }

    private struct ProposalConfirmBody: Encodable {
        let candidateStart: String?
        let task: CoachTaskDraft
    }
}
