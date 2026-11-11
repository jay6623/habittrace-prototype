import Foundation

// Contracts for `POST /chat` (SSE) and the coach conversation endpoints.
// Mirrors `lib/api.ts` and `lib/coach-chart.ts` in the PWA.

nonisolated struct ChatHistoryMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
}

/// A data-only chart computed by the backend.
nonisolated struct CoachChartSpec: Codable, Equatable, Sendable {
    nonisolated struct Point: Codable, Equatable, Sendable {
        var label: String
        var value: Double
        var sampleSize: Int
        var completed: Int?
    }

    nonisolated struct Period: Codable, Equatable, Sendable {
        var start: String
        var end: String
    }

    var chartType: String
    var title: String
    var xAxis: String
    var yAxis: String
    var units: String
    var period: Period
    var sampleSize: Int
    var intervalDays: Int?
    var focus: String?
    var note: String
    var data: [Point]

    /// The PWA's `isCoachChart` guard: bounded, internally consistent data.
    var isValid: Bool {
        func text(_ value: String, _ max: Int) -> Bool { !value.isEmpty && value.count <= max }
        func day(_ value: String) -> Bool { TaskTimeFormatting.date(fromISODate: value) != nil && value.count == 10 }

        guard chartType == "bar" || chartType == "line",
              units == "percent" || units == "count",
              intervalDays == nil || intervalDays == 1 || intervalDays == 7,
              text(title, 200), text(xAxis, 100), text(yAxis, 100), text(note, 500),
              day(period.start), day(period.end), period.start <= period.end,
              sampleSize >= 5,
              (2...90).contains(data.count),
              Set(data.map(\.label)).count == data.count,
              data.reduce(0, { $0 + $1.sampleSize }) == sampleSize
        else { return false }

        return data.allSatisfy { point in
            guard text(point.label, 200), point.value.isFinite, point.value >= 0, point.sampleSize > 0 else { return false }
            if units == "percent", point.value > 100 { return false }
            if let completed = point.completed {
                guard units == "percent", completed >= 0, completed <= point.sampleSize else { return false }
                return abs(point.value - Double(completed) / Double(point.sampleSize) * 100) <= 0.050000001
            }
            return true
        }
    }

    /// Two-period aggregate comparisons render as categorical bars.
    var forDisplay: CoachChartSpec {
        guard chartType == "line", intervalDays == nil, data.count == 2,
              data.allSatisfy({ $0.label.wholeMatch(of: /^\d{4}-\d{2}-\d{2} – \d{4}-\d{2}-\d{2}$/) != nil })
        else { return self }
        var copy = self
        copy.chartType = "bar"
        copy.focus = "comparison"
        copy.title = "Completion rate by period"
        copy.xAxis = "Recorded period"
        return copy
    }
}

/// A `TaskCreate` body as the coach proposes it; editable before confirm.
nonisolated struct CoachTaskDraft: Codable, Equatable, Sendable {
    var title: String
    var notes: String?
    var taskCategory: String
    var plannedStartTime: String
    var plannedDate: String?
    var plannedDurationMin: Int
    var importance: Int
    var energyLevel: Int
    var focusLevel: Int
    var totalTasksToday: Int
    var timezoneName: String?
}

nonisolated struct CoachTimeOption: Codable, Equatable, Sendable {
    var start: String
    var end: String
    var score: Double
    var reasons: [String]
}

nonisolated struct CoachTaskProposal: Codable, Equatable, Sendable {
    var id: String
    var task: CoachTaskDraft
    var options: [CoachTimeOption]
}

nonisolated struct DailyScheduledTask: Codable, Equatable, Sendable {
    var taskId: String
    var title: String
    var estimatedDurationMinutes: Int
    var category: String
    var scheduledStart: String
    var scheduledEnd: String
    var predictedSuccessProbability: Double
    var explanation: String?
    var createdTaskId: String?
}

nonisolated struct DailyUnscheduledTask: Codable, Equatable, Sendable {
    var taskId: String
    var title: String
    var estimatedDurationMinutes: Int
    var reason: String
}

nonisolated struct DailySchedule: Codable, Equatable, Sendable {
    var id: String
    var selectedDate: String
    var timezoneName: String
    var status: String
    var scheduledTasks: [DailyScheduledTask]
    var unscheduledTasks: [DailyUnscheduledTask]
    var warnings: [String]
}

/// Either a single task with recommended times or a whole-day draft.
nonisolated enum CoachProposal: Equatable, Sendable {
    case task(CoachTaskProposal)
    case dailySchedule(DailySchedule)

    init?(json: Any, decoder: JSONDecoder) {
        guard let object = json as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        if object["kind"] as? String == "daily_schedule" {
            guard let schedule = object["schedule"],
                  let scheduleData = try? JSONSerialization.data(withJSONObject: schedule),
                  let decoded = try? decoder.decode(DailySchedule.self, from: scheduleData) else { return nil }
            self = .dailySchedule(decoded)
        } else {
            guard let decoded = try? decoder.decode(CoachTaskProposal.self, from: data) else { return nil }
            self = .task(decoded)
        }
    }
}

/// One parsed `data:` frame from the chat stream.
nonisolated enum ChatStreamEvent: Equatable, Sendable {
    case conversation(id: String)
    case token(String)
    case chart(CoachChartSpec)
    case proposal(CoachProposal)
    case done
}

nonisolated struct ChatStreamError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Parses SSE `data:` lines into events. Malformed JSON is skipped, as
/// the PWA does; `{"error": …}` becomes a thrown error.
nonisolated enum ChatStreamParser {
    static func events(fromLine line: String, decoder: JSONDecoder) throws -> [ChatStreamEvent] {
        guard line.hasPrefix("data: ") else { return [] }
        let payload = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        if let error = object["error"] as? String {
            throw ChatStreamError(message: error)
        }

        var events: [ChatStreamEvent] = []
        if let token = object["token"] as? String {
            events.append(.token(token))
        }
        if let id = object["conversation_id"] as? String {
            events.append(.conversation(id: id))
        }
        if let proposal = object["proposal"], let decoded = CoachProposal(json: proposal, decoder: decoder) {
            events.append(.proposal(decoded))
        }
        if let chart = object["chart"],
           let chartData = try? JSONSerialization.data(withJSONObject: chart),
           let decoded = try? decoder.decode(CoachChartSpec.self, from: chartData),
           decoded.isValid {
            events.append(.chart(decoded))
        }
        return events
    }
}

/// `GET /chat/conversations/latest`.
nonisolated struct CoachConversation: Decodable, Sendable {
    nonisolated struct Message: Decodable, Sendable {
        nonisolated struct Metadata: Decodable, Sendable {
            var chart: CoachChartSpec?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                chart = try? container.decodeIfPresent(CoachChartSpec.self, forKey: .chart)
            }

            enum CodingKeys: String, CodingKey { case chart }
        }

        var id: String
        var role: String
        var content: String
        var createdAt: String?
        var metadata: Metadata?
    }

    var id: String
    var messages: [Message]
    var pendingProposals: [CoachProposal]

    enum CodingKeys: String, CodingKey {
        case id, messages, pendingProposals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messages = (try? container.decode([Message].self, forKey: .messages)) ?? []
        let raw = (try? container.decode([AnyJSONValue].self, forKey: .pendingProposals)) ?? []
        let proposalDecoder = JSONDecoder()
        proposalDecoder.keyDecodingStrategy = .convertFromSnakeCase
        pendingProposals = raw.compactMap { CoachProposal(json: $0.value, decoder: proposalDecoder) }
    }
}

/// Carries an arbitrary JSON subtree through `Decodable` so proposals can
/// be parsed by their `kind` discriminator.
nonisolated struct AnyJSONValue: Decodable, Sendable {
    /// Plain Foundation JSON values (dictionaries, arrays, strings,
    /// numbers, bools, NSNull), which are immutable once decoded.
    nonisolated(unsafe) let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dictionary = try? container.decode([String: AnyJSONValue].self) {
            value = dictionary.mapValues(\.value)
        } else if let array = try? container.decode([AnyJSONValue].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            value = NSNull()
        }
    }
}
