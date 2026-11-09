import SwiftUI

/// Two-by-two grid of the PWA's four Today metrics. The Unlogged tile
/// opens the unlogged list, as in the PWA.
struct TodayStatsGrid: View {
    let model: TodayViewModel
    var onOpenUnlogged: () -> Void = {}

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

            Button {
                onOpenUnlogged()
            } label: {
                HTStatTile(
                    title: "Unlogged",
                    value: "\(model.unloggedCount)",
                    caption: model.unloggedCount > 0 ? "Tap to log them" : "All caught up",
                    style: model.unloggedCount > 0 ? .attention : .neutral
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens past plans that still need an outcome")
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
