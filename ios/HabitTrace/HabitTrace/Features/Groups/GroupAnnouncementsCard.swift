import SwiftUI

/// Announcements for the selected group: owner/admin composer, a paged
/// list (four per page), and a tap to open the thread.
struct GroupAnnouncementsCard: View {
    @ObservedObject var viewModel: GroupsViewModel
    let onOpen: (GroupAnnouncement) -> Void

    static let pageSize = 4

    @State private var isComposing = false
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var page = 0

    private var pageCount: Int {
        max(1, Int((Double(viewModel.announcements.count) / Double(Self.pageSize)).rounded(.up)))
    }

    private var visibleAnnouncements: ArraySlice<GroupAnnouncement> {
        let start = min(page * Self.pageSize, viewModel.announcements.count)
        let end = min(start + Self.pageSize, viewModel.announcements.count)
        return viewModel.announcements[start..<end]
    }

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPosting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Announcements")
                        .font(.htBodyStrong)
                        .foregroundStyle(HTColor.textPrimary)
                    Text(viewModel.canPostAnnouncements
                        ? "Members can open a thread to reply."
                        : "Only the owner or an admin can post. Open an announcement to read it and reply.")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                }
                Spacer(minLength: HTSpacing.sm)
                if viewModel.canPostAnnouncements, !isComposing {
                    Button("Create announcement") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isComposing = true
                        }
                    }
                    .buttonStyle(.htSecondary(minHeight: 36))
                }
            }

            if isComposing {
                composer
            }

            if let message = errorMessage ?? viewModel.announcementsError {
                GroupInlineError(text: message)
            }

            if viewModel.isLoadingAnnouncements, viewModel.announcements.isEmpty {
                Text("Loading announcements…")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textSecondary)
            } else if viewModel.announcements.isEmpty {
                Text("No announcements yet.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            } else {
                VStack(spacing: HTSpacing.sm) {
                    ForEach(visibleAnnouncements) { announcement in
                        announcementRow(announcement)
                    }
                }

                if viewModel.announcements.count > Self.pageSize {
                    pager
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
        .onChange(of: viewModel.announcements.count) { _, _ in
            page = min(page, pageCount - 1)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            TextField("Announcement title", text: $title)
                .htField()
                .disabled(isPosting)
                .onChange(of: title) { _, value in
                    if value.count > GroupHelpers.announcementTitleMaxLength {
                        title = String(value.prefix(GroupHelpers.announcementTitleMaxLength))
                    }
                }
            TextField("Description", text: $bodyText, axis: .vertical)
                .lineLimit(3...8)
                .htField()
                .disabled(isPosting)
                .onChange(of: bodyText) { _, value in
                    if value.count > GroupHelpers.announcementBodyMaxLength {
                        bodyText = String(value.prefix(GroupHelpers.announcementBodyMaxLength))
                    }
                }
            HStack(spacing: HTSpacing.sm) {
                Button(isPosting ? "Posting…" : "Post announcement") {
                    Task { await post() }
                }
                .buttonStyle(.htPrimary)
                .disabled(!canPost)
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isComposing = false
                    }
                    title = ""
                    bodyText = ""
                    errorMessage = nil
                    viewModel.clearAnnouncementsError()
                }
                .buttonStyle(.htSecondary)
                .disabled(isPosting)
            }
        }
        .padding(HTSpacing.md)
        .background(HTColor.surfaceMuted)
        .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
    }

    private func post() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            try await viewModel.postAnnouncement(title: trimmedTitle, body: trimmedBody)
            title = ""
            bodyText = ""
            page = 0
            withAnimation(.easeOut(duration: 0.2)) {
                isComposing = false
            }
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't post that announcement.")
        }
    }

    // MARK: - List

    private func announcementRow(_ announcement: GroupAnnouncement) -> some View {
        let author = viewModel.authorName(id: announcement.authorId, name: announcement.authorName)
        return Button {
            onOpen(announcement)
        } label: {
            VStack(alignment: .leading, spacing: HTSpacing.xs) {
                Text(announcement.title)
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: HTSpacing.sm) {
                    MemberAvatarView(name: author, avatarURL: announcement.authorAvatarUrl, size: 28)
                    Text(author)
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HTColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HTSpacing.md)
            .background(HTColor.surfaceMuted)
            .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the thread")
    }

    private var pager: some View {
        HStack(spacing: HTSpacing.sm) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button("\(index + 1)") {
                    page = index
                }
                .buttonStyle(.htChip(isSelected: index == page))
                .accessibilityLabel("Page \(index + 1)")
                .accessibilityAddTraits(index == page ? [.isSelected] : [])
            }
        }
    }
}

/// One announcement with its replies and a reply field.
struct GroupAnnouncementThreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: GroupsViewModel
    let announcementID: String

    @State private var reply = ""
    @State private var isReplying = false
    @State private var errorMessage: String?

    private var announcement: GroupAnnouncement? {
        viewModel.announcements.first { $0.id == announcementID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let announcement {
                    VStack(alignment: .leading, spacing: HTSpacing.lg) {
                        VStack(alignment: .leading, spacing: HTSpacing.md) {
                            Text(announcement.title)
                                .htSectionTitle()
                            authorLine(
                                id: announcement.authorId,
                                name: announcement.authorName,
                                avatarURL: announcement.authorAvatarUrl,
                                createdAt: announcement.createdAt,
                                size: 36
                            )
                            Text(announcement.body)
                                .font(.htBody)
                                .foregroundStyle(HTColor.textStrong)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .htCard()

                        VStack(alignment: .leading, spacing: HTSpacing.md) {
                            Text("Replies")
                                .font(.htBodyStrong)
                                .foregroundStyle(HTColor.textPrimary)
                            if announcement.replies.isEmpty {
                                Text("No replies yet.")
                                    .font(.htBody)
                                    .foregroundStyle(HTColor.textMuted)
                            } else {
                                ForEach(announcement.replies) { item in
                                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                                        authorLine(
                                            id: item.authorId,
                                            name: item.authorName,
                                            avatarURL: item.authorAvatarUrl,
                                            createdAt: item.createdAt,
                                            size: 28
                                        )
                                        Text(item.body)
                                            .font(.htBody)
                                            .foregroundStyle(HTColor.textStrong)
                                    }
                                    .padding(HTSpacing.md)
                                    .background(HTColor.surfaceMuted)
                                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                                }
                            }

                            if let errorMessage {
                                GroupInlineError(text: errorMessage)
                            }

                            TextField("Write a reply…", text: $reply, axis: .vertical)
                                .lineLimit(2...6)
                                .htField()
                                .disabled(isReplying)
                                .onChange(of: reply) { _, value in
                                    if value.count > GroupHelpers.announcementBodyMaxLength {
                                        reply = String(value.prefix(GroupHelpers.announcementBodyMaxLength))
                                    }
                                }
                            Button(isReplying ? "Replying…" : "Reply") {
                                Task { await postReply(to: announcement) }
                            }
                            .buttonStyle(.htPrimary(fullWidth: true))
                            .disabled(isReplying || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .htCard()
                    }
                    .padding(.horizontal, HTSpacing.screenHorizontal)
                    .padding(.top, HTSpacing.lg)
                    .padding(.bottom, HTSpacing.screenBottom)
                } else {
                    HTEmptyState(
                        title: "Announcement unavailable",
                        message: "It may have been removed.",
                        systemImage: "megaphone"
                    )
                    .htCard()
                    .padding(HTSpacing.screenHorizontal)
                }
            }
            .background(HTColor.surfaceMuted)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isReplying)
                }
            }
        }
    }

    private func authorLine(id: String, name: String?, avatarURL: String?, createdAt: String, size: CGFloat) -> some View {
        let author = viewModel.authorName(id: id, name: name)
        return HStack(spacing: HTSpacing.sm) {
            MemberAvatarView(name: author, avatarURL: avatarURL, size: size)
            VStack(alignment: .leading, spacing: 1) {
                Text(author)
                    .font(.htCaptionStrong)
                    .foregroundStyle(HTColor.textPrimary)
                    .lineLimit(1)
                Text(GroupHelpers.formatTimestamp(createdAt, timeZone: viewModel.timeZone))
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }
        }
    }

    private func postReply(to announcement: GroupAnnouncement) async {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isReplying = true
        errorMessage = nil
        defer { isReplying = false }

        do {
            try await viewModel.postReply(to: announcement, body: trimmed)
            reply = ""
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't post that reply.")
        }
    }
}
