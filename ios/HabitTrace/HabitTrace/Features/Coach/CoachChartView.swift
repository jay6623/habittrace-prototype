import Charts
import SwiftUI

/// Renders a backend-computed coach chart with its caption, note, and an
/// expandable data table. Mirrors `components/coach-chart.tsx`.
struct CoachChartView: View {
    let spec: CoachChartSpec

    private var chart: CoachChartSpec { spec.forDisplay }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text(chart.title)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textPrimary)
            Text("\(chart.period.start) – \(chart.period.end) · \(chart.sampleSize) plotted observations")
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            plot
                .frame(height: 220)

            Text(chart.note)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            DisclosureGroup("View chart data") {
                VStack(spacing: 0) {
                    tableRow(chart.xAxis, chart.yAxis, chart.units == "percent" ? "Completed / total" : "Sample size", isHeader: true)
                    ForEach(chart.data, id: \.label) { point in
                        tableRow(point.label, valueText(point), countText(point))
                    }
                }
            }
            .font(.htCaption)
            .foregroundStyle(HTColor.textSecondary)
        }
        .padding(HTSpacing.md)
        .background(HTColor.surface)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                .strokeBorder(HTColor.border, lineWidth: 1)
        }
        .accessibilityLabel(chart.title)
    }

    @ViewBuilder
    private var plot: some View {
        let series = Self.series(for: chart)
        Chart {
            if chart.chartType == "bar" {
                ForEach(series, id: \.label) { point in
                    if let value = point.value {
                        BarMark(x: .value(chart.xAxis, Self.tick(point.label)), y: .value(chart.yAxis, value))
                            .foregroundStyle(HTColor.success600)
                            .cornerRadius(4)
                    }
                }
            } else {
                ForEach(series, id: \.label) { point in
                    if let value = point.value {
                        LineMark(x: .value(chart.xAxis, Self.tick(point.label)), y: .value(chart.yAxis, value), series: .value("Run", point.run))
                            .foregroundStyle(HTColor.success600)
                        PointMark(x: .value(chart.xAxis, Self.tick(point.label)), y: .value(chart.yAxis, value))
                            .foregroundStyle(HTColor.success400)
                    }
                }
            }
        }
        .chartXScale(domain: series.map { Self.tick($0.label) })
        .chartYScale(domain: chart.units == "percent" ? 0...100 : 0...max(1, (series.compactMap(\.value).max() ?? 1) * 1.1))
        .chartXAxis {
            AxisMarks(values: Self.axisValues(series.map { Self.tick($0.label) })) { _ in
                AxisGridLine().foregroundStyle(HTColor.border.opacity(0.5))
                AxisValueLabel().foregroundStyle(HTColor.textSecondary).font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(HTColor.border.opacity(0.5))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(chart.units == "percent" ? "\(Int(number))%" : "\(Int(number))")
                            .foregroundStyle(HTColor.textSecondary)
                    }
                }
            }
        }
        .chartXAxisLabel(chart.xAxis, alignment: .center)
        .chartYAxisLabel(chart.yAxis)
    }

    private func tableRow(_ a: String, _ b: String, _ c: String, isHeader: Bool = false) -> some View {
        HStack(alignment: .top, spacing: HTSpacing.sm) {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(width: 64, alignment: .leading)
            Text(c).frame(width: 110, alignment: .leading)
        }
        .font(isHeader ? .htCaptionStrong : .htCaption)
        .padding(.vertical, 4)
    }

    private func valueText(_ point: CoachChartSpec.Point) -> String {
        chart.units == "percent" ? "\(InsightsViewModel.number(point.value))%" : InsightsViewModel.number(point.value)
    }

    private func countText(_ point: CoachChartSpec.Point) -> String {
        if let completed = point.completed {
            return "\(completed)/\(point.sampleSize) completed"
        }
        return "n=\(point.sampleSize)"
    }

    // MARK: - Series helpers (from `lib/coach-chart.ts`)

    struct SeriesPoint {
        let label: String
        let value: Double?
        /// Contiguous recorded days share a run so gaps break the line.
        let run: Int
    }

    /// Missing days stay nil so a line never implies unrecorded outcomes.
    static func series(for chart: CoachChartSpec) -> [SeriesPoint] {
        func plain(_ points: [CoachChartSpec.Point]) -> [SeriesPoint] {
            points.map { SeriesPoint(label: $0.label, value: $0.value, run: 0) }
        }
        guard chart.chartType == "line",
              let first = chart.data.first?.label, let last = chart.data.last?.label,
              let start = TaskTimeFormatting.date(fromISODate: first),
              let end = TaskTimeFormatting.date(fromISODate: last),
              end >= start, end.timeIntervalSince(start) <= 90 * 86_400
        else { return plain(chart.data) }

        let byLabel = Dictionary(uniqueKeysWithValues: chart.data.map { ($0.label, $0) })
        let step = chart.intervalDays ?? 1
        var result: [SeriesPoint] = []
        var run = 0
        var previousMissing = false
        var cursor = start
        while cursor <= end {
            let label = TaskTimeFormatting.isoDate(from: cursor)
            if let point = byLabel[label] {
                if previousMissing { run += 1 }
                result.append(SeriesPoint(label: label, value: point.value, run: run))
                previousMissing = false
            } else {
                result.append(SeriesPoint(label: label, value: nil, run: run))
                previousMissing = true
            }
            guard let next = Calendar.current.date(byAdding: .day, value: step, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Short axis labels: "2026-11-03" → "Nov 3"; ranges keep both ends.
    static func tick(_ label: String) -> String {
        if let date = TaskTimeFormatting.date(fromISODate: label), label.count == 10 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        let parts = label.components(separatedBy: " – ")
        if parts.count == 2,
           let startDate = TaskTimeFormatting.date(fromISODate: parts[0]),
           let endDate = TaskTimeFormatting.date(fromISODate: parts[1]) {
            return "\(startDate.formatted(.dateTime.month(.abbreviated).day())) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return label
    }

    /// At most six evenly spaced tick labels.
    static func axisValues(_ labels: [String]) -> [String] {
        guard labels.count > 6 else { return labels }
        let stride = Int((Double(labels.count) / 6).rounded(.up))
        return labels.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
}
