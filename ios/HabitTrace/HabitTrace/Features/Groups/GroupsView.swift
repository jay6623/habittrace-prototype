import SwiftUI

/// Groups tab placeholder. Group creation, invite codes, and shared
/// tasks are added once the groups endpoints are wired up.
struct GroupsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                HTEmptyState(
                    title: "Groups aren't available yet",
                    message: "Plan together with friends and track shared tasks. This section is coming soon.",
                    systemImage: "person.2"
                )
                .htCard()
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Groups")
        }
    }
}

#Preview {
    GroupsView()
}
