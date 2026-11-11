import SwiftUI

/// Round member avatar: the remote image when available, else the
/// name's first letter on slate-950. Mirrors `components/group/member-avatar`.
struct MemberAvatarView: View {
    let name: String
    var avatarURL: String?
    var size: CGFloat = 36

    var body: some View {
        AvatarView(url: resolvedURL, initials: GroupHelpers.memberInitial(name), size: size)
            .accessibilityHidden(true)
    }

    private var resolvedURL: URL? {
        guard let trimmed = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }
}

/// Small tinted pill for roles and priorities.
struct GroupPill: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.htCaptionStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, HTSpacing.sm)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(Capsule())
            .lineLimit(1)
    }

    /// owner amber, admin sky, member slate.
    static func role(_ role: GroupRole) -> GroupPill {
        switch role {
        case .owner: GroupPill(text: role.rawValue.uppercased(), background: HTColor.warning100, foreground: HTColor.warning700)
        case .admin: GroupPill(text: role.rawValue.uppercased(), background: HTColor.info100, foreground: HTColor.info700)
        case .member: GroupPill(text: role.rawValue.uppercased(), background: HTColor.surfaceSecondary, foreground: HTColor.textSecondary)
        }
    }

    /// high rose, medium amber, low slate; raw lower-case text.
    static func priority(_ priority: GroupTaskPriority) -> GroupPill {
        switch priority {
        case .high: GroupPill(text: priority.rawValue, background: HTColor.danger100, foreground: HTColor.danger700)
        case .medium: GroupPill(text: priority.rawValue, background: HTColor.warning100, foreground: HTColor.warning700)
        case .low: GroupPill(text: priority.rawValue, background: HTColor.surfaceSecondary, foreground: HTColor.textSecondary)
        }
    }
}

/// Thin progress bar coloured by completion rate: ≥70 emerald, ≥50 amber,
/// else rose; slate when there is nothing to measure.
struct GroupProgressBar: View {
    /// 0–100, or nil when no tasks are assigned.
    let rate: Int?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HTColor.surfaceSecondary)
                Capsule()
                    .fill(rate.map(Self.tone) ?? HTColor.border)
                    .frame(width: proxy.size.width * CGFloat(min(max(rate ?? 0, 0), 100)) / 100)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    nonisolated static func tone(_ rate: Int) -> Color {
        if rate >= 70 { return HTColor.success400 }
        if rate >= 50 { return HTColor.accentAmber }
        return HTColor.accentRose
    }

    /// Text colour matching `tone`.
    static func textTone(_ rate: Int) -> Color {
        if rate >= 70 { return HTColor.success600 }
        if rate >= 50 { return HTColor.warning500 }
        return HTColor.danger600
    }
}

/// Rose notice used inside the Groups forms for inline errors.
struct GroupInlineError: View {
    let text: String

    var body: some View {
        AuthNotice(text: text, tone: .error)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Bold form label used across the Groups sheets.
struct GroupFieldLabel: View {
    let text: String
    var hint: String?

    var body: some View {
        HStack(spacing: HTSpacing.xs) {
            Text(text)
                .font(.htBodyStrong)
                .foregroundStyle(HTColor.textStrong)
            if let hint {
                Text(hint)
                    .font(.htBody)
                    .foregroundStyle(HTColor.textTertiary)
            }
        }
    }
}
