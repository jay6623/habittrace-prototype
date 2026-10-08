import SwiftUI

/// Today tab placeholder.
///
/// Establishes the header and surface of the daily planning screen.
/// Stats, the outlook card, the hero card, and actions are added in a
/// later checkpoint; nothing here reads or writes task data yet.
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.xl) {
                    header

                    placeholderCard
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(TaskTimeFormatting.headerDate(.now))
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)

            Text("Today")
                .htPageTitle()

            Text("See what's next, start it, and record how it went.")
                .font(.htBody)
                .foregroundStyle(HTColor.textSecondary)
        }
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HTEyebrowLabel(text: "Daily planning")

            Text("Your day at a glance")
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)

            Text(
                "This screen will show today's progress, what's up next, and quick actions to start a plan or log an outcome."
            )
            .font(.htBody)
            .foregroundStyle(HTColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }
}

#Preview {
    TodayView()
}
