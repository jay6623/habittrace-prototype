import SwiftUI

/// Insights tab placeholder. Success rates, patterns, and charts are
/// added once the analytics endpoints are wired up.
struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                HTEmptyState(
                    title: "Insights aren't available yet",
                    message: "See what works for you: success rates, best times of day, and why plans slip. This section is coming soon.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .htCard()
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
