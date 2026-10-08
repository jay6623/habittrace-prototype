import SwiftUI

/// Plans tab. Hosts the existing task list for now; the PWA-style
/// day stepper and filters arrive in a later checkpoint.
struct PlansView: View {
    var body: some View {
        TaskListView()
    }
}

#Preview {
    PlansView()
        .environmentObject(AuthManager())
        .environmentObject(TaskService())
}
