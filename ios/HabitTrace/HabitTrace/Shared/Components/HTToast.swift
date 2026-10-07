import SwiftUI

/// A transient message shown at the top of the screen.
///
/// Matches the Today page toast in the PWA: solid emerald or rose,
/// auto-dismissed after 3.5 seconds.
struct HTToastMessage: Identifiable, Equatable {
    enum Kind {
        case success
        case error
    }

    let id = UUID()
    let text: String
    let kind: Kind

    static func success(_ text: String) -> HTToastMessage {
        HTToastMessage(text: text, kind: .success)
    }

    static func error(_ text: String) -> HTToastMessage {
        HTToastMessage(text: text, kind: .error)
    }
}

/// Visual for a single toast.
struct HTToastView: View {
    let message: HTToastMessage

    var body: some View {
        Label(message.text, systemImage: symbolName)
            .font(.htBodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, HTSpacing.lg)
            .padding(.vertical, HTSpacing.md)
            .background(background)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .shadow(color: background.opacity(0.35), radius: 12, y: 6)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var background: Color {
        switch message.kind {
        case .success: HTColor.success600
        case .error: HTColor.danger600
        }
    }

    private var symbolName: String {
        switch message.kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

/// Presents a toast bound to an optional message and clears it after a delay.
struct HTToastModifier: ViewModifier {
    @Binding var message: HTToastMessage?
    var duration: Duration = .seconds(3.5)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HTToastView(message: message)
                        .padding(.horizontal, HTSpacing.lg)
                        .padding(.top, HTSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            self.message = nil
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: message)
            .task(id: message?.id) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                message = nil
            }
    }
}

extension View {
    /// Shows `message` as a top toast and clears it after `duration`.
    func htToast(
        _ message: Binding<HTToastMessage?>,
        duration: Duration = .seconds(3.5)
    ) -> some View {
        modifier(HTToastModifier(message: message, duration: duration))
    }
}

#Preview("Toast") {
    @Previewable @State var message: HTToastMessage? = .success("Plan started")

    VStack(spacing: HTSpacing.md) {
        Button("Show success") {
            message = .success("Outcome saved")
        }
        .buttonStyle(.htPrimary)

        Button("Show error") {
            message = .error("Couldn't start plan")
        }
        .buttonStyle(.htSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HTColor.surfaceMuted)
    .htToast($message)
}
