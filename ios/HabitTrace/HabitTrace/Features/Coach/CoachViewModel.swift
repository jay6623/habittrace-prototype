import Combine
import Foundation

/// One bubble in the coach conversation.
struct CoachMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    enum ProposalStatus: Equatable {
        case pending
        case confirmed
        case cancelled
    }

    let id: UUID
    let role: Role
    var content: String
    var chart: CoachChartSpec?
    var proposal: CoachProposal?
    var proposalStatus: ProposalStatus?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        chart: CoachChartSpec? = nil,
        proposal: CoachProposal? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.chart = chart
        self.proposal = proposal
        self.proposalStatus = proposal == nil ? nil : .pending
    }
}

/// Drives the coach chat: history restore, SSE streaming, proposal
/// confirm/dismiss, and clearing. Mirrors `components/coach-chat.tsx`.
@MainActor
final class CoachViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String

    static let suggestions = [
        "Plan my day: finish my report, go to the gym, and buy groceries.",
        "Review my last 30 days. What is the clearest pattern, and what should I try next?",
        "When do I complete focused work most reliably? Include the sample size.",
        "Why might my Study plans be failing? Use my duration and interruption history.",
        "Help me choose one realistic planning experiment for this week.",
    ]

    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var conversationID: String?
    @Published private(set) var isLoadingHistory = true
    @Published private(set) var isStreaming = false
    @Published private(set) var streamText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyProposalMessageID: UUID?

    private let apiClient: APIClient
    private let taskService: TaskService?
    private let accessTokenProvider: AccessTokenProvider

    init(
        apiClient: APIClient = APIClient(),
        taskService: TaskService? = nil,
        accessTokenProvider: @escaping AccessTokenProvider
    ) {
        self.apiClient = apiClient
        self.taskService = taskService
        self.accessTokenProvider = accessTokenProvider
    }

    var showsWelcome: Bool {
        !isLoadingHistory && messages.isEmpty && !isStreaming
    }

    // MARK: - History

    /// Restores the latest persisted conversation. Failure is silent: the
    /// coach stays usable before persistence is configured.
    func loadHistory() async {
        defer { isLoadingHistory = false }
        do {
            let token = try await accessTokenProvider()
            guard let conversation = try await apiClient.fetchLatestConversation(accessToken: token) else { return }
            conversationID = conversation.id
            var restored = conversation.messages.map { message in
                CoachMessage(
                    role: message.role == "user" ? .user : .assistant,
                    content: message.content,
                    chart: message.metadata?.chart.flatMap { $0.isValid ? $0 : nil }
                )
            }
            restored += conversation.pendingProposals.map { proposal in
                CoachMessage(
                    role: .assistant,
                    content: "This recommendation is still waiting for your confirmation.",
                    proposal: proposal
                )
            }
            messages = restored
        } catch {
            // Keep the empty conversation.
        }
    }

    // MARK: - Sending

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        errorMessage = nil

        let history = messages.map { ChatHistoryMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content) }
        messages.append(CoachMessage(role: .user, content: trimmed))
        isStreaming = true
        streamText = ""
        defer {
            isStreaming = false
            streamText = ""
        }

        do {
            let token = try await accessTokenProvider()
            var full = ""
            var proposal: CoachProposal?
            var chart: CoachChartSpec?

            for try await event in apiClient.streamChat(
                accessToken: token,
                message: trimmed,
                history: history,
                conversationID: conversationID
            ) {
                switch event {
                case .token(let token):
                    full += token
                    streamText = full
                case .conversation(let id):
                    conversationID = id
                case .proposal(let received):
                    proposal = received
                case .chart(let received):
                    if chart == nil { chart = received }
                case .done:
                    break
                }
            }

            messages.append(CoachMessage(
                role: .assistant,
                content: full.trimmingTrailingWhitespace(),
                chart: chart,
                proposal: proposal
            ))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    // MARK: - Proposals

    func confirmTask(messageID: UUID, proposal: CoachTaskProposal, candidateStart: String?, draft: CoachTaskDraft) async {
        guard busyProposalMessageID == nil else { return }
        busyProposalMessageID = messageID
        defer { busyProposalMessageID = nil }

        do {
            let token = try await accessTokenProvider()
            let created = try await apiClient.confirmProposal(
                accessToken: token,
                proposalID: proposal.id,
                candidateStart: candidateStart,
                task: draft
            )
            taskService?.upsertTask(created)
            setProposalStatus(.confirmed, for: messageID)
            let when = [created.plannedDate, created.plannedStartTime].compactMap { $0 }.joined(separator: " at ")
            messages.append(CoachMessage(
                role: .assistant,
                content: "“\(created.title)” has been added to your schedule on \(when). Check your Calendar or Plans tab!"
            ))
        } catch {
            messages.append(CoachMessage(
                role: .assistant,
                content: "Sorry, couldn't add the task: \(ErrorPresentation.message(for: error))"
            ))
        }
    }

    func dismissTask(messageID: UUID, proposal: CoachTaskProposal) async {
        guard busyProposalMessageID == nil else { return }
        busyProposalMessageID = messageID
        defer {
            busyProposalMessageID = nil
            setProposalStatus(.cancelled, for: messageID)
        }
        if let token = try? await accessTokenProvider() {
            try? await apiClient.dismissProposal(accessToken: token, proposalID: proposal.id)
        }
    }

    func confirmDailyPlan(messageID: UUID, schedule: DailySchedule) async {
        guard busyProposalMessageID == nil else { return }
        busyProposalMessageID = messageID
        defer { busyProposalMessageID = nil }

        do {
            let token = try await accessTokenProvider()
            let confirmed = try await apiClient.confirmDailySchedule(accessToken: token, scheduleID: schedule.id)
            setProposalStatus(.confirmed, for: messageID)
            if let taskService {
                await taskService.loadTasks(accessToken: token)
            }
            messages.append(CoachMessage(
                role: .assistant,
                content: "\(confirmed.scheduledTasks.count) tasks have been added to your schedule. You can review them in Calendar or Plans."
            ))
        } catch {
            messages.append(CoachMessage(
                role: .assistant,
                content: "Sorry, couldn't confirm the daily plan: \(ErrorPresentation.message(for: error))"
            ))
        }
    }

    func cancelDailyPlan(messageID: UUID) {
        setProposalStatus(.cancelled, for: messageID)
    }

    // MARK: - Clearing

    /// Archives the server conversation when there is one, then clears the
    /// local view even if archiving failed.
    func clearConversation() async {
        if let conversationID, let token = try? await accessTokenProvider() {
            try? await apiClient.archiveConversation(accessToken: token, conversationID: conversationID)
        }
        conversationID = nil
        messages = []
        errorMessage = nil
    }

    private func setProposalStatus(_ status: CoachMessage.ProposalStatus, for messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].proposalStatus = status
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var copy = self
        while let last = copy.last, last.isWhitespace || last.isNewline {
            copy.removeLast()
        }
        return copy
    }
}
