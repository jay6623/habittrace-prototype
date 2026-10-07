import SwiftUI

/// Section header with a title and an optional trailing action.
///
/// Matches the PWA pattern of `text-lg font-bold` beside a small link.
struct HTSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .htSectionTitle()

            Spacer(minLength: HTSpacing.sm)

            trailing
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textMuted)
        }
    }
}

extension HTSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Small uppercase label used above values and groups.
struct HTEyebrowLabel: View {
    let text: String
    var color: Color = HTColor.textMuted

    var body: some View {
        Text(text)
            .htEyebrow(color: color)
    }
}

/// Inline "label: value" meta text, such as "30 min · Work".
struct HTMetaText: View {
    let parts: [String]
    var color: Color = HTColor.textMuted

    init(_ parts: String..., color: Color = HTColor.textMuted) {
        self.parts = parts.filter { !$0.isEmpty }
        self.color = color
    }

    var body: some View {
        Text(parts.joined(separator: " · "))
            .font(.htCaption)
            .foregroundStyle(color)
    }
}

/// Full-width empty state used inside cards and lists.
struct HTEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "checkmark.circle"

    var body: some View {
        VStack(spacing: HTSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(HTColor.textTertiary)

            Text(title)
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)

            if let message {
                Text(message)
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HTSpacing.xl)
    }
}

/// Amber banner shown when the device is offline.
struct HTNoticeBanner: View {
    let text: String
    var systemImage: String = "wifi.slash"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.htCaptionStrong)
            .foregroundStyle(HTColor.warning700)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HTSpacing.md)
            .padding(.vertical, HTSpacing.sm)
            .background(HTColor.warning50)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.md, style: .continuous)
                    .strokeBorder(HTColor.warning100, lineWidth: 1)
            }
    }
}

#Preview("Labels") {
    VStack(alignment: .leading, spacing: HTSpacing.lg) {
        HTSectionHeader("Remaining today") {
            Text("View all")
        }

        HTSectionHeader("No trailing")

        HTEyebrowLabel(text: "Up next")

        HTMetaText("2:00 PM", "30 min", "Work")

        HTNoticeBanner(text: "You're offline. Changes will sync when you reconnect.")

        HTEmptyState(
            title: "You're caught up",
            message: "Nothing left to log for today."
        )
        .htCard()
    }
    .padding(HTSpacing.screenHorizontal)
    .background(HTColor.surfaceMuted)
}
