import Foundation

struct APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTasks(accessToken: String) async throws -> [HabitTraceTask] {
        let url = APIConfiguration.baseURL.appending(path: "tasks")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            return try decoder.decode(
                [HabitTraceTask].self,
                from: data
            )
        } catch {
            throw APIError.decoding(error)
        }
    }

    func completeTask(
        accessToken: String,
        taskId: String
    ) async throws -> HabitTraceExecution {
        let url = APIConfiguration.baseURL.appending(path: "executions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let now = ISO8601DateFormatter().string(from: Date())

        let body = ExecutionCreateRequest(
            taskId: taskId,
            actualStartTime: now,
            actualEndTime: now,
            interruptionCount: 0,
            stoppedEarly: false,
            taskStatus: "success",
            failureReason: nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            return try decoder.decode(
                HabitTraceExecution.self,
                from: data
            )
        } catch {
            throw APIError.decoding(error)
        }
    }

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
        totalTasksToday: Int
    ) async throws -> HabitTraceTask {
        let url = APIConfiguration.baseURL.appending(path: "tasks")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

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
            totalTasksToday: totalTasksToday
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            return try decoder.decode(
                HabitTraceTask.self,
                from: data
            )
        } catch {
            throw APIError.decoding(error)
        }
    }
}

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
}

private struct ExecutionCreateRequest: Encodable {
    let taskId: String
    let actualStartTime: String
    let actualEndTime: String
    let interruptionCount: Int
    let stoppedEarly: Bool
    let taskStatus: String
    let failureReason: String?
}
