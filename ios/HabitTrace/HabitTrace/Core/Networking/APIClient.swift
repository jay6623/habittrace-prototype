import Foundation

/// HTTP client for the HabitTrace API.
///
/// Stateless: callers pass the Supabase access token for each request.
/// Field names follow the backend's snake_case schemas through the
/// coding strategies in `makeDecoder()` and `makeEncoder()`.
struct APIClient {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Tasks

    /// `GET /tasks`, optionally filtered to one `"yyyy-MM-dd"` date.
    /// The server orders by the raw time string; sort client-side.
    func fetchTasks(accessToken: String, date: String? = nil) async throws -> [HabitTraceTask] {
        var query: [URLQueryItem] = []
        if let date {
            query.append(URLQueryItem(name: "date", value: date))
        }

        let request = try makeRequest(.get, path: "tasks", query: query, accessToken: accessToken)
        return try await send(request)
    }

    /// `POST /tasks`.
    func createTask(
        accessToken: String,
        title: String,
        notes: String?,
        taskCategory: String,
        plannedStartTime: String,
        plannedDate: String?,
        plannedDurationMin: Int,
        importance: Int,
        energyLevel: Int,
        focusLevel: Int,
        totalTasksToday: Int,
        timezoneName: String = TimeZone.current.identifier
    ) async throws -> HabitTraceTask {
        let body = TaskCreateRequest(
            title: title,
            notes: notes,
            taskCategory: taskCategory,
            plannedStartTime: plannedStartTime,
            plannedDate: plannedDate,
            plannedDurationMin: plannedDurationMin,
            importance: importance,
            energyLevel: energyLevel,
            focusLevel: focusLevel,
            totalTasksToday: totalTasksToday,
            timezoneName: timezoneName
        )

        let request = try makeRequest(.post, path: "tasks", body: body, accessToken: accessToken)
        return try await send(request)
    }

    /// `PATCH /tasks/{id}`. The server rejects explicit nulls for every
    /// field except `notes`, so omitted fields are left unchanged.
    func updateTask(
        accessToken: String,
        taskId: String,
        title: String,
        notes: String?,
        taskCategory: String,
        plannedStartTime: String,
        plannedDate: String?,
        plannedDurationMin: Int,
        importance: Int,
        energyLevel: Int,
        focusLevel: Int
    ) async throws -> HabitTraceTask {
        let body = TaskUpdateRequest(
            title: title,
            notes: notes,
            taskCategory: taskCategory,
            plannedStartTime: plannedStartTime,
            plannedDate: plannedDate,
            plannedDurationMin: plannedDurationMin,
            importance: importance,
            energyLevel: energyLevel,
            focusLevel: focusLevel
        )

        let request = try makeRequest(
            .patch,
            path: "tasks/\(taskId)",
            body: body,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `DELETE /tasks/{id}`. Returns 204.
    func deleteTask(accessToken: String, taskId: String) async throws {
        let request = try makeRequest(.delete, path: "tasks/\(taskId)", accessToken: accessToken)
        _ = try await perform(request)
    }

    /// Quick completion: logs one finished successful execution for the
    /// task with the current time as both start and end.
    func completeTask(accessToken: String, taskId: String) async throws -> HabitTraceExecution {
        let now = Date()
        let outcome = ExecutionOutcomeRequest(
            taskStatus: "success",
            outcomeStatus: .completed,
            completionRatio: 1,
            actualStartTime: now,
            actualEndTime: now
        )

        return try await logExecution(
            accessToken: accessToken,
            taskId: taskId,
            outcome: outcome,
            idempotencyKey: nil
        )
    }

    // MARK: - Executions

    /// `GET /executions`, or `GET /executions?active=true` for executions
    /// that have started but not finished. Newest first.
    func fetchExecutions(accessToken: String, activeOnly: Bool = false) async throws -> [HabitTraceExecution] {
        let query = activeOnly ? [URLQueryItem(name: "active", value: "true")] : []
        let request = try makeRequest(.get, path: "executions", query: query, accessToken: accessToken)
        return try await send(request)
    }

    /// `POST /executions/start`. Idempotent: returns the existing active
    /// execution if one exists. 409 when the task is not pending.
    func startExecution(accessToken: String, taskId: String) async throws -> HabitTraceExecution {
        let request = try makeRequest(
            .post,
            path: "executions/start",
            body: ExecutionStartRequest(taskId: taskId),
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `POST /executions`: records a finished outcome in one call. If the
    /// task has an active execution the server completes it instead.
    /// 409 on rule violations.
    func logExecution(
        accessToken: String,
        taskId: String,
        outcome: ExecutionOutcomeRequest,
        idempotencyKey: String?
    ) async throws -> HabitTraceExecution {
        let body = ExecutionLogRequest(
            taskId: taskId,
            idempotencyKey: idempotencyKey,
            outcome: outcome
        )

        let request = try makeRequest(.post, path: "executions", body: body, accessToken: accessToken)
        return try await send(request)
    }

    /// `PATCH /executions/{id}/complete`: finishes an active execution.
    /// 422 on rule violations.
    func completeExecution(
        accessToken: String,
        executionId: String,
        outcome: ExecutionOutcomeRequest
    ) async throws -> HabitTraceExecution {
        let request = try makeRequest(
            .patch,
            path: "executions/\(executionId)/complete",
            body: outcome,
            accessToken: accessToken
        )
        return try await send(request)
    }

    /// `PATCH /executions/{id}`: revises an already finished execution and
    /// syncs the parent task's status. 422 on rule violations.
    func reviseExecution(
        accessToken: String,
        executionId: String,
        outcome: ExecutionOutcomeRequest
    ) async throws -> HabitTraceExecution {
        let request = try makeRequest(
            .patch,
            path: "executions/\(executionId)",
            body: outcome,
            accessToken: accessToken
        )
        return try await send(request)
    }

    // MARK: - Transport

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private func makeRequest(
        _ method: Method,
        path: String,
        query: [URLQueryItem] = [],
        accessToken: String
    ) throws -> URLRequest {
        let baseURL = APIConfiguration.baseURL.appending(path: path)

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeRequest(
        _ method: Method,
        path: String,
        body: some Encodable,
        accessToken: String
    ) throws -> URLRequest {
        var request = try makeRequest(method, path: path, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeEncoder().encode(body)
        return request
    }

    /// Sends the request and decodes a JSON response.
    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await perform(request)

        do {
            return try makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Sends the request and returns the raw body after checking the status.
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpStatus(httpResponse.statusCode, detail: Self.errorDetail(in: data))
        }

        return data
    }

    /// Extracts the backend's `{"detail": "..."}` message when present.
    /// FastAPI validation errors send `detail` as an array; those are
    /// flattened to their messages.
    private static func errorDetail(in data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let detail = dictionary["detail"]
        else {
            return nil
        }

        if let text = detail as? String {
            return text
        }

        if let items = detail as? [[String: Any]] {
            let messages = items.compactMap { $0["msg"] as? String }
            return messages.isEmpty ? nil : messages.joined(separator: " ")
        }

        return nil
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Request bodies

    private struct TaskCreateRequest: Encodable {
        let title: String
        let notes: String?
        let taskCategory: String
        let plannedStartTime: String
        let plannedDate: String?
        let plannedDurationMin: Int
        let importance: Int
        let energyLevel: Int
        let focusLevel: Int
        let totalTasksToday: Int
        let timezoneName: String
    }

    private struct TaskUpdateRequest: Encodable {
        let title: String
        let notes: String?
        let taskCategory: String
        let plannedStartTime: String
        let plannedDate: String?
        let plannedDurationMin: Int
        let importance: Int
        let energyLevel: Int
        let focusLevel: Int
    }

    private struct ExecutionStartRequest: Encodable {
        let taskId: String
    }
}
