import SwiftUI

/// Two-by-two grid of the PWA's four Today metrics.
struct TodayStatsGrid: View {
    let model: TodayViewModel

    private let columns = [
        GridItem(.flexible(), spacing: HTSpacing.md),
        GridItem(.flexible(), spacing: HTSpacing.md),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: HTSpacing.md) {
            HTStatTile(
                title: "Completed",
                value: "\(model.completedCount)"
            )

            HTStatTile(
                title: "Remaining",
                value: "\(model.remainingTasks.count)"
            )

            HTStatTile(
                title: "Planned minutes",
                value: "\(model.plannedMinutes)"
            )

            HTStatTile(
                title: "Unlogged",
                value: "\(model.unloggedCount)",
                caption: model.unloggedCount > 0 ? "From earlier days" : nil,
                style: model.unloggedCount > 0 ? .attention : .neutral
            )
        }
    }
}

#if DEBUG
#Preview {
    TodayStatsGrid(model: TodayViewModel(tasks: HabitTraceTask.previewTasks))
        .padding(HTSpacing.screenHorizontal)
        .background(HTColor.surfaceMuted)
}
#endif
