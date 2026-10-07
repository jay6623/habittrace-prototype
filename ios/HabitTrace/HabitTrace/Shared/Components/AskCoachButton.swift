import SwiftUI

/// Floating "Ask coach" pill anchored to the bottom trailing corner.
///
/// Matches the PWA's `btn-primary fixed bottom-24 right-4` button.
struct AskCoachButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Ask coach", systemImage: "sparkles")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.htPrimary(minHeight: HTControlHeight.comfortable))
        .clipShape(Capsule())
        .shadow(color: HTColor.brand.opacity(0.25), radius: 12, y: 6)
        .accessibilityHint("Opens the AI coach")
    }
}

extension View {
    /// Overlays a floating Ask Coach button in the bottom trailing corner.
    func askCoachOverlay(action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            AskCoachButton(action: action)
                .padding(.trailing, HTSpacing.lg)
                .padding(.bottom, HTSpacing.lg)
        }
    }
}

#Preview("Ask coach") {
    HTColor.surfaceMuted
        .ignoresSafeArea()
        .askCoachOverlay {}
}
