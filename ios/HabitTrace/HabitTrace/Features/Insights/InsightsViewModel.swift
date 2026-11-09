import Combine
import Foundation

/// Loads the analytics summary and personalized insights for one period.
/// The personalized call is best-effort, as in the PWA: its failure leaves
/// the summary visible.
@MainActor
final class InsightsViewModel: ObservableObject {
    typealias AccessTokenProvider = @MainActor () async throws -> String

    @Published var period: InsightsPeriod = .week {
        didSet {
            guard period != oldValue else { return }
            Task { await load() }
        }
    }
    @Published private(set) var summary: AnalyticsSummary?
    @Published private(set) var personalized: PersonalizedInsights?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let apiClient: APIClient
    private let accessTokenProvider: AccessTokenProvider
    private var generation = 0

    init(apiClient: APIClient = APIClient(), accessTokenProvider: @escaping AccessTokenProvider) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
    }

    var isEmpty: Bool {
        (summary?.totalTasks ?? 0) == 0
    }

    func load() async {
        generation += 1
        let current = generation
        let requested = period
        isLoading = true

        do {
            let token = try await accessTokenProvider()
            async let summaryTask = apiClient.fetchAnalyticsSummary(accessToken: token, period: requested)
            async let personalizedTask: PersonalizedInsights? = {
                try? await apiClient.fetchPersonalizedInsights(
                    accessToken: token,
                    period: requested,
                    endDate: TaskTimeFormatting.isoDate(from: .now)
                )
            }()
            let (loadedSummary, loadedPersonalized) = try await (summaryTask, personalizedTask)
            guard current == generation else { return }
            summary = loadedSummary
            personalized = loadedPersonalized
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = "We couldn’t load your insights. Please try again."
        }

        if current == generation {
            isLoading = false
        }
    }

    // MARK: - Derived display values

    /// Stat tiles in the PWA's order.
    var stats: [InsightStat] {
        guard let summary else { return [] }
        return [
            InsightStat(label: "Overall success rate", value: "\(Self.number(summary.successRate))%", caption: "based on completed tasks", isPositive: true),
            InsightStat(label: "Total tasks", value: "\(summary.totalTasks)", caption: "in this \(period.noun)", isPositive: true),
            InsightStat(label: "Category to revisit", value: summary.mostFailedCategory, caption: "highest failure count", isPositive: false),
            InsightStat(label: "Best time of day", value: summary.bestTimeOfDay, caption: "highest success rate", isPositive: true),
            InsightStat(label: "Avg interruptions", value: summary.avgInterruptions.map(Self.number) ?? "—", caption: "per task", isPositive: false),
            InsightStat(label: "Avg importance", value: Self.number(summary.avgImportance), caption: "out of 5", isPositive: true),
        ]
    }

    /// Hour buckets in the server's order (dictionary order is lost in
    /// decoding, so sort by the bucket's starting hour).
    var hourBuckets: [(label: String, rate: Double)] {
        guard let summary else { return [] }
        return summary.successByHour
            .map { (label: $0.key, rate: $0.value) }
            .sorted { Self.bucketOrder($0.label) < Self.bucketOrder($1.label) }
    }

    var failureCategories: [(label: String, count: Int)] {
        guard let summary else { return [] }
        return summary.failureByCategory
            .map { (label: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }

    var failureReasons: [(label: String, count: Int)] {
        guard let summary else { return [] }
        return summary.failureByReason
            .map { (label: Self.titleCased($0.key), count: $0.value) }
            .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }

    /// "Key insights" tiles, each shown only when its condition holds.
    var keyInsights: [KeyInsight] {
        guard let summary else { return [] }
        var items: [KeyInsight] = []
        if summary.bestTimeOfDay != "—" {
            let rate = summary.successByHour[summary.bestTimeOfDay] ?? 0
            items.append(KeyInsight(tone: .success, title: "Best: \(summary.bestTimeOfDay)", detail: "\(Self.number(rate))% success rate"))
        }
        if summary.mostFailedCategory != "—", summary.mostFailedCategory != "N/A" {
            let count = summary.failureByCategory[summary.mostFailedCategory] ?? 0
            items.append(KeyInsight(tone: .danger, title: "Most failures: \(summary.mostFailedCategory)", detail: "\(count) failed tasks"))
        }
        if let interruptions = summary.avgInterruptions, interruptions > 1.5 {
            items.append(KeyInsight(tone: .warning, title: "High interruptions: \(Self.number(interruptions))/task", detail: "Try scheduling focus blocks"))
        }
        if summary.successRate > 0 {
            items.append(KeyInsight(tone: .info, title: "Success rate: \(Self.number(summary.successRate))%", detail: "\(summary.totalTasks) tasks tracked"))
        }
        return items
    }

    /// Whole numbers print without a decimal; others keep one place.
    nonisolated static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    nonisolated static func titleCased(_ snake: String) -> String {
        snake.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Orders "6-9 AM", "9-12 PM", … by their 24-hour start.
    nonisolated static func bucketOrder(_ label: String) -> Int {
        let parts = label.split(separator: " ")
        guard let range = parts.first, let startText = range.split(separator: "-").first,
              let start = Int(startText) else { return Int.max }
        let meridiem = parts.count > 1 ? String(parts[1]) : "AM"
        // "9-12 PM" starts at 9 AM; "9-12 AM" starts at 9 PM.
        if meridiem == "PM" {
            return start == 12 ? 12 : (start < 9 ? start + 12 : start)
        }
        return start >= 9 && start < 12 && label.hasSuffix("AM") && label.hasPrefix("9-12") ? 21 : start
    }
}

nonisolated struct InsightStat: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let value: String
    let caption: String
    let isPositive: Bool
}

nonisolated struct KeyInsight: Identifiable, Equatable, Sendable {
    enum Tone: Sendable {
        case success
        case danger
        case warning
        case info
    }

    var id: String { title }
    let tone: Tone
    let title: String
    let detail: String
}
