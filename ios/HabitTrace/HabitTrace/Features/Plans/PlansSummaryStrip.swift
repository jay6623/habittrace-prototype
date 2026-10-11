import SwiftUI

/// Four tiles driven entirely by `PlansSummary`, which is derived from
/// the same items the filter and rows use.
struct PlansSummaryStrip: View {
    let summary: PlansSummary

    private let columns = [
        GridItem(.flexible(), spacing: HTSpacing.md),
        GridItem(.flexible(), spacing: HTSpacing.md),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: HTSpacing.md) {
            HTStatTile(
                title: "Planned",
                value: summary.plannedDurationText,
                caption: planCountText
            )

            HTStatTile(
                title: "Completed",
                value: "\(summary.completed)/\(summary.total)"
            )

            HTStatTile(
                title: "In progress",
                value: "\(summary.inProgress)"
            )

            HTStatTile(
                title: "Remaining",
                value: "\(summary.remaining)",
                caption: summary.remaining == 1 ? "plan left" : "plans left"
            )
        }
    }

    private var planCountText: String {
        summary.total == 1 ? "1 plan" : "\(summary.total) plans"
    }
}

#if DEBUG
#Preview {
    let items = HabitTraceTask.previewTasks.map { PlanListItem(task: $0, activeExecution: nil) }
    PlansSummaryStrip(summary: PlansSummary(items: items))
        .padding(HTSpacing.screenHorizontal)
        .background(HTColor.surfaceMuted)
}
#endif
