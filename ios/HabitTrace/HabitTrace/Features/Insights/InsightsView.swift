import Charts
import SwiftUI

/// Insights tab entry.
struct InsightsView: View {
    @EnvironmentObject private var authManager: AuthManager
    var onPlanSomething: () -> Void = {}

    var body: some View {
        InsightsScreen(accessTokenProvider: authManager.validAccessToken, onPlanSomething: onPlanSomething)
    }
}

/// "What works for you": period picker, personalized patterns, six stat
/// tiles, five charts, and key insights. Mirrors `/dashboard/analytics`.
struct InsightsScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel: InsightsViewModel
    let onPlanSomething: () -> Void

    init(accessTokenProvider: @escaping InsightsViewModel.AccessTokenProvider, onPlanSomething: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(accessTokenProvider: accessTokenProvider))
        self.onPlanSomething = onPlanSomething
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    header
                    content
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(spacing: HTSpacing.md) {
                AvatarView(url: authManager.avatarURL, initials: authManager.avatarInitials, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HTEyebrowLabel(text: "Analytics")
                    Text("What works for you")
                        .htPageTitle()
                }
                Spacer()
            }

            Picker("Period", selection: $viewModel.period) {
                ForEach(InsightsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if let message = viewModel.errorMessage, viewModel.summary == nil {
            VStack(alignment: .leading, spacing: HTSpacing.md) {
                Text("Insights unavailable")
                    .htSectionTitle()
                Text(message)
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.htSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .htPanel()
            .accessibilityElement(children: .contain)
        } else if viewModel.isLoading && viewModel.summary == nil {
            Text("Loading your insights…")
                .font(.htBody)
                .foregroundStyle(HTColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .htPanel()
        } else if let summary = viewModel.summary, summary.totalTasks == 0 {
            VStack(spacing: HTSpacing.md) {
                Text("Your story starts with one plan")
                    .htPageTitle()
                    .multilineTextAlignment(.center)
                Text("There are no plans in this period yet. Record a few outcomes to discover what works for you.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
                    .multilineTextAlignment(.center)
                Button("Plan something small") {
                    onPlanSomething()
                }
                .buttonStyle(.htPrimary)
            }
            .frame(maxWidth: .infinity)
            .htPanel()
        } else if let summary = viewModel.summary {
            if viewModel.errorMessage != nil {
                HTNoticeBanner(text: "Insights unavailable. Showing your last loaded data.", systemImage: "exclamationmark.triangle")
            }
            personalizedCard
            statsGrid
            executionTrendCard(summary)
            successRateCard(summary)
            timeOfDayCard
            failureByCategoryCard
            failureReasonsCard
            keyInsightsCard
        }
    }

    // MARK: - Personalized patterns

    private var personalizedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: HTSpacing.md) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HTEyebrowLabel(text: "Personalized patterns", color: HTColor.success700)
                    Text("What AI learned from this \(viewModel.period.learnedFromText)")
                        .htSectionTitle()
                    Text("Completed outcomes are compared across category, time, weekday, and plan length.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textSecondary)
                }
                Spacer(minLength: HTSpacing.sm)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\((viewModel.personalized?.confidenceLabel ?? "learning").capitalized) signal")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.success700)
                    Text("\(viewModel.personalized?.sampleCount ?? 0) recorded outcomes")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
                .padding(.horizontal, HTSpacing.md)
                .padding(.vertical, HTSpacing.sm)
                .background(HTColor.surface)
                .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                        .strokeBorder(HTColor.success100, lineWidth: 1)
                }
            }
            .padding(HTSpacing.lg)

            Divider().overlay(HTColor.success100)

            if let personalized = viewModel.personalized, personalized.available {
                VStack(spacing: HTSpacing.sm) {
                    patternTile(
                        eyebrow: "Strongest pattern",
                        color: HTColor.success700,
                        ring: HTColor.success100,
                        text: personalized.strongestPattern?.message ?? "No clear positive pattern yet in this period."
                    )
                    patternTile(
                        eyebrow: "Pattern to watch",
                        color: HTColor.warning700,
                        ring: HTColor.warning100,
                        text: personalized.patternToWatch?.message ?? "No repeated friction pattern yet in this period."
                    )
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        HTEyebrowLabel(text: "Change from before", color: HTColor.info700)
                        Text(changeText(personalized))
                            .font(.htStatValue)
                            .foregroundStyle(HTColor.textPrimary)
                        Text(changeCaption(personalized))
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .htCard(padding: HTSpacing.md)
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        HTEyebrowLabel(text: "Next experiment", color: Color(hex: 0x4D7C0F))
                        Text(personalized.recommendedExperiment.title)
                            .font(.htBodyStrong)
                            .foregroundStyle(HTColor.textPrimary)
                        Text(personalized.recommendedExperiment.detail)
                            .font(.htCaption)
                            .foregroundStyle(HTColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .htCard(padding: HTSpacing.md)
                }
                .padding(HTSpacing.lg)
            } else {
                Text("Record outcomes in this period to reveal your personal patterns.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HTSpacing.lg)
            }

            Divider().overlay(HTColor.success100)

            Text("These are history-based tendencies, not predictions of past outcomes or guarantees.")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HTSpacing.lg)
                .padding(.vertical, HTSpacing.sm)
        }
        .background(
            LinearGradient(
                colors: [HTColor.success50, HTColor.surface, Color(hex: 0xF7FEE7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(Color(hex: 0xA7F3D0), lineWidth: 1)
        }
    }

    private func patternTile(eyebrow: String, color: Color, ring: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            HTEyebrowLabel(text: eyebrow, color: color)
            Text(text)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(padding: HTSpacing.md)
    }

    private func changeText(_ personalized: PersonalizedInsights) -> String {
        guard let change = personalized.changePercentagePoints else { return "—" }
        let sign = change > 0 ? "+" : ""
        return "\(sign)\(InsightsViewModel.number(change)) pts"
    }

    private func changeCaption(_ personalized: PersonalizedInsights) -> String {
        guard let previous = personalized.previousSuccessRate, let now = personalized.successRate else {
            return "Not enough previous-period data"
        }
        return "\(InsightsViewModel.number(now))% now · \(InsightsViewModel.number(previous))% before"
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: HTSpacing.sm), GridItem(.flexible(), spacing: HTSpacing.sm)], spacing: HTSpacing.sm) {
            ForEach(viewModel.stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                    Text(stat.value)
                        .font(.htSectionTitle)
                        .foregroundStyle(HTColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(stat.caption)
                        .font(.htCaption)
                        .foregroundStyle(stat.isPositive ? HTColor.success600 : HTColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .htCard(padding: HTSpacing.md)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Charts

    private func chartCard(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(title)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
            Text(subtitle)
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
                .padding(.bottom, HTSpacing.sm)
            content()
                .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(padding: HTSpacing.md)
    }

    private func executionTrendCard(_ summary: AnalyticsSummary) -> some View {
        chartCard("Execution trend", "Planned vs completed minutes") {
            Chart {
                ForEach(summary.executionTrend, id: \.label) { point in
                    AreaMark(x: .value("Period", point.label), y: .value("Minutes", point.plannedMins), series: .value("Series", "Planned (min)"))
                        .foregroundStyle(HTColor.brand.opacity(0.05))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Period", point.label), y: .value("Minutes", point.plannedMins), series: .value("Series", "Planned (min)"))
                        .foregroundStyle(by: .value("Series", "Planned (min)"))
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Period", point.label), y: .value("Minutes", point.completedMins), series: .value("Series", "Completed (min)"))
                        .foregroundStyle(HTColor.accentEmerald.opacity(0.05))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Period", point.label), y: .value("Minutes", point.completedMins), series: .value("Series", "Completed (min)"))
                        .foregroundStyle(by: .value("Series", "Completed (min)"))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(["Planned (min)": HTColor.brand, "Completed (min)": HTColor.accentEmerald])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(HTColor.textTertiary) } }
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(HTColor.surfaceSecondary); AxisValueLabel().foregroundStyle(HTColor.textTertiary) } }
        }
    }

    private func successRateCard(_ summary: AnalyticsSummary) -> some View {
        chartCard("Success rate over time", "% of tasks completed successfully") {
            Chart {
                ForEach(summary.executionTrend, id: \.label) { point in
                    AreaMark(x: .value("Period", point.label), y: .value("Success rate", point.successRate))
                        .foregroundStyle(HTColor.accentEmerald.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Period", point.label), y: .value("Success rate", point.successRate))
                        .foregroundStyle(HTColor.accentEmerald)
                        .interpolationMethod(.catmullRom)
                        .symbol(Circle())
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(HTColor.textTertiary) } }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(HTColor.surfaceSecondary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))%").foregroundStyle(HTColor.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var timeOfDayCard: some View {
        chartCard("Performance by time of day", "When you’re most likely to succeed") {
            Chart {
                ForEach(viewModel.hourBuckets, id: \.label) { bucket in
                    BarMark(x: .value("Time", bucket.label), y: .value("Success rate", bucket.rate))
                        .foregroundStyle(Self.hourColor(bucket.label))
                        .cornerRadius(6)
                }
            }
            .chartXScale(domain: viewModel.hourBuckets.map(\.label))
            .chartYScale(domain: 0...100)
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(HTColor.textTertiary).font(.system(size: 9)) } }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(HTColor.surfaceSecondary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))%").foregroundStyle(HTColor.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var failureByCategoryCard: some View {
        chartCard("Planning obstacles by category", "Which types of tasks fail most") {
            if viewModel.failureCategories.isEmpty {
                emptyChart("No failure data yet")
            } else {
                Chart {
                    ForEach(Array(viewModel.failureCategories.enumerated()), id: \.element.label) { index, item in
                        BarMark(x: .value("Failed tasks", item.count), y: .value("Category", item.label))
                            .foregroundStyle(Self.categoryColors[index % Self.categoryColors.count])
                            .cornerRadius(6)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(HTColor.surfaceSecondary)
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)").foregroundStyle(HTColor.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks { AxisValueLabel().foregroundStyle(HTColor.textMuted) } }
            }
        }
    }

    private var failureReasonsCard: some View {
        chartCard("Why tasks fail", "Most common failure reasons") {
            if viewModel.failureReasons.isEmpty {
                emptyChart("No failure data yet")
            } else {
                HStack(spacing: HTSpacing.md) {
                    Chart {
                        ForEach(Array(viewModel.failureReasons.enumerated()), id: \.element.label) { index, item in
                            SectorMark(angle: .value("Count", item.count), innerRadius: .ratio(0.65), angularInset: 1)
                                .foregroundStyle(Self.reasonColors[index % Self.reasonColors.count])
                        }
                    }
                    .frame(width: 140)

                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        ForEach(Array(viewModel.failureReasons.enumerated()), id: \.element.label) { index, item in
                            HStack(spacing: HTSpacing.xs) {
                                Circle()
                                    .fill(Self.reasonColors[index % Self.reasonColors.count])
                                    .frame(width: 8, height: 8)
                                Text("\(item.label): \(item.count)")
                                    .font(.htCaption)
                                    .foregroundStyle(HTColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var keyInsightsCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text("Key insights")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
            Text("Observations from your data")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)
                .padding(.bottom, HTSpacing.sm)

            VStack(spacing: HTSpacing.sm) {
                ForEach(viewModel.keyInsights) { insight in
                    HStack(alignment: .top, spacing: HTSpacing.sm) {
                        Circle()
                            .fill(Self.toneColors(insight.tone).dot)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.htCaptionStrong)
                                .foregroundStyle(Self.toneColors(insight.tone).title)
                            Text(insight.detail)
                                .font(.htCaption)
                                .foregroundStyle(Self.toneColors(insight.tone).detail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(HTSpacing.sm)
                    .background(Self.toneColors(insight.tone).background)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(padding: HTSpacing.md)
    }

    private func emptyChart(_ text: String) -> some View {
        Text(text)
            .font(.htBody)
            .foregroundStyle(HTColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Palettes (from the PWA)

    private static func hourColor(_ label: String) -> Color {
        switch label {
        case "6-9 AM", "9-12 PM": HTColor.accentEmerald
        case "12-3 PM", "6-9 PM": HTColor.accentAmber
        case "3-6 PM": HTColor.accentSky
        case "9-12 AM": HTColor.accentRose
        default: HTColor.textTertiary
        }
    }

    private static let categoryColors: [Color] = [
        HTColor.accentSky, HTColor.accentViolet, HTColor.accentEmerald,
        HTColor.textTertiary, HTColor.accentAmber, HTColor.accentRose,
    ]

    private static let reasonColors: [Color] = [
        HTColor.brand, HTColor.accentSky, HTColor.accentAmber, HTColor.accentViolet,
        HTColor.border, HTColor.accentEmerald, HTColor.accentRose,
    ]

    private static func toneColors(_ tone: KeyInsight.Tone) -> (background: Color, dot: Color, title: Color, detail: Color) {
        switch tone {
        case .success: (HTColor.success50, HTColor.success400, Color(hex: 0x064E3B), HTColor.success700)
        case .danger: (HTColor.danger50, HTColor.accentRose, Color(hex: 0x881337), HTColor.danger700)
        case .warning: (HTColor.warning50, HTColor.accentAmber, Color(hex: 0x78350F), HTColor.warning700)
        case .info: (HTColor.info50, HTColor.accentSky, Color(hex: 0x0C4A6E), HTColor.info700)
        }
    }
}
