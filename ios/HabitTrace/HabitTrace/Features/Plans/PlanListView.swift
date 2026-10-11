import SwiftUI

/// Renders already-filtered, already-sorted items from the view model.
struct PlanListView: View {
    let items: [PlanListItem]
    let isBusy: Bool
    let onAction: (PlanAction, PlanListItem) -> Void

    var body: some View {
        LazyVStack(spacing: HTSpacing.md) {
            ForEach(items) { item in
                PlanRow(item: item, isBusy: isBusy) { action in
                    onAction(action, item)
                }
            }
        }
    }
}

/// The two non-error empty states, kept visually distinct from failures.
struct PlansEmptyStateView: View {
    let state: PlansEmptyState
    let onAddPlan: () -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: HTSpacing.md) {
            switch state {
            case .noPlans:
                HTEmptyState(
                    title: "No plans for this day",
                    message: "Add one small plan. You can adjust it as your day changes.",
                    systemImage: "calendar.badge.plus"
                )

                Button("Add a plan") {
                    onAddPlan()
                }
                .buttonStyle(.htPrimary)

            case .noMatches:
                HTEmptyState(
                    title: "No plans match this filter",
                    message: "Choose another status to see your plans.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )

                Button("Show all plans") {
                    onShowAll()
                }
                .buttonStyle(.htSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, HTSpacing.lg)
        .htCard()
    }
}

/// Shown while a different day is loading, so the previous day's plans
/// are never displayed under the new date.
struct PlansLoadingView: View {
    var body: some View {
        VStack(spacing: HTSpacing.sm) {
            ProgressView()

            Text("Loading plans…")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HTSpacing.xxl)
        .htCard()
        .accessibilityElement(children: .combine)
    }
}

/// Load failure with a retry, distinct from the empty states.
struct PlansErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Label("Couldn't load plans for this date", systemImage: "exclamationmark.triangle")
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.danger700)

            Text(message)
                .font(.htCaption)
                .foregroundStyle(HTColor.textSecondary)

            Button("Try again") {
                onRetry()
            }
            .buttonStyle(.htSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard(background: HTColor.danger50)
    }
}

#if DEBUG
#Preview("States") {
    ScrollView {
        VStack(spacing: HTSpacing.lg) {
            PlansEmptyStateView(state: .noPlans, onAddPlan: {}, onShowAll: {})
            PlansEmptyStateView(state: .noMatches, onAddPlan: {}, onShowAll: {})
            PlansLoadingView()
            PlansErrorView(message: "You're offline or the server can't be reached.", onRetry: {})
        }
        .padding(HTSpacing.screenHorizontal)
    }
    .background(HTColor.surfaceMuted)
}
#endif
