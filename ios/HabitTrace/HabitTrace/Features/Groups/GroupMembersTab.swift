import SwiftUI

/// Members tab: one card per member with role controls and progress.
struct GroupMembersTab: View {
    @ObservedObject var viewModel: GroupsViewModel
    let onShowInvite: () -> Void

    private var isOwner: Bool { viewModel.activeDetail?.group.role == .owner }

    var body: some View {
        VStack(spacing: HTSpacing.md) {
            ForEach(viewModel.members) { member in
                memberCard(member)
            }

            if viewModel.members.count == 1 {
                soloCard
            }
        }
    }

    private func memberCard(_ member: GroupMember) -> some View {
        let name = viewModel.memberName(member)
        let progress = viewModel.stats.progressByMember[member.userId] ?? GroupStats.MemberProgress()
        let isUpdating = viewModel.updatingMemberID == member.userId

        return VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.md) {
                MemberAvatarView(name: name, avatarURL: member.avatarUrl, size: 44)
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text(name)
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                        .lineLimit(2)
                    GroupPill.role(member.role)
                }
                Spacer(minLength: HTSpacing.sm)
            }

            if isOwner, member.role != .owner {
                Button(roleButtonTitle(member, isUpdating: isUpdating)) {
                    Task { await viewModel.setRole(member.role == .admin ? .member : .admin, for: member) }
                }
                .buttonStyle(.htSecondary(fullWidth: true))
                .disabled(viewModel.updatingMemberID != nil)
            }

            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                HStack {
                    Text("Assigned tasks")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                    Spacer()
                    Text("\(progress.assigned)")
                        .font(.htCaptionStrong)
                        .foregroundStyle(HTColor.textPrimary)
                }
                if let rate = progress.rate {
                    Text("Completed \(progress.done) · \(rate)%")
                        .font(.htCaption)
                        .foregroundStyle(GroupProgressBar.textTone(rate))
                } else {
                    Text("No tasks yet")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
                GroupProgressBar(rate: progress.rate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func roleButtonTitle(_ member: GroupMember, isUpdating: Bool) -> String {
        if isUpdating { return "Updating…" }
        return member.role == .admin ? "Demote to member" : "Promote to admin"
    }

    private var soloCard: some View {
        VStack(spacing: HTSpacing.sm) {
            Text("It's just you so far")
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)
            Text("Share the invite code so teammates can join.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
                .multilineTextAlignment(.center)
            Button("Show invite code", action: onShowInvite)
                .buttonStyle(.htSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(HTSpacing.xl)
        .overlay {
            RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                .strokeBorder(HTColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
    }
}
