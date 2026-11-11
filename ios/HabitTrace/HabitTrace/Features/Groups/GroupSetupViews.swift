import SwiftUI

/// Which setup sheet is open.
enum GroupSetupSheet: String, Identifiable {
    case create
    case join

    var id: String { rawValue }
}

/// No-groups landing: two large cards for creating or joining a group.
struct GroupSetupEmptyView: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(spacing: HTSpacing.lg) {
            VStack(spacing: HTSpacing.sm) {
                Text("Start coordinating together")
                    .htPageTitle()
                    .multilineTextAlignment(.center)
                Text("Create a shared space for your team, or join an existing group with an invite code.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HTSpacing.sm)

            setupCard(
                symbol: "+",
                symbolBackground: HTColor.ink,
                title: "Create group",
                detail: "Start a new group and invite teammates when you're ready.",
                action: onCreate
            )
            setupCard(
                symbol: "↗",
                symbolBackground: HTColor.success600,
                title: "Join group",
                detail: "Enter an invite code from a teammate to get access.",
                action: onJoin
            )
        }
    }

    private func setupCard(
        symbol: String,
        symbolBackground: Color,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: HTSpacing.lg) {
                Text(symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(symbolBackground)
                    .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    Text(title)
                        .htSectionTitle()
                    Text(detail)
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .htCard(padding: HTSpacing.xxl, cornerRadius: HTRadius.xl)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// "New or existing group" panel shown above the page when the member
/// already belongs to a group.
struct GroupSetupPanel: View {
    let onCreate: () -> Void
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New or existing group")
                        .font(.htCardTitle)
                        .foregroundStyle(HTColor.textPrimary)
                    Text("Create another group or join one with an invite code.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                }
                Spacer(minLength: HTSpacing.sm)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HTColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(HTColor.surfaceSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Button(action: onCreate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create group")
                        .font(.htCardTitle)
                        .foregroundStyle(.white)
                    Text("Make a new shared workspace")
                        .font(.htBody)
                        .foregroundStyle(HTColor.borderStrong)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HTSpacing.xl)
                .padding(.vertical, HTSpacing.lg)
                .background(HTColor.ink)
                .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onJoin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join group")
                        .font(.htCardTitle)
                        .foregroundStyle(HTColor.textPrimary)
                    Text("Use a teammate's invite code")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HTSpacing.xl)
                .padding(.vertical, HTSpacing.lg)
                .background(HTColor.surface)
                .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                        .strokeBorder(HTColor.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .htCard(padding: HTSpacing.xl)
    }
}

/// "Create a group" sheet.
struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Creates the group; throws so the sheet can show the mapped error.
    let onCreate: (String) async throws -> Void

    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    Text("Give your group a clear name. You'll get an invite code to share so teammates can join.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)

                    GroupFieldLabel(text: "Group name")
                    TextField("e.g. Study & Work Group", text: $name)
                        .textInputAutocapitalization(.words)
                        .htField()
                        .disabled(isCreating)
                        .onChange(of: name) { _, value in
                            if value.count > GroupHelpers.groupNameMaxLength {
                                name = String(value.prefix(GroupHelpers.groupNameMaxLength))
                            }
                        }
                        .onSubmit { Task { await submit() } }

                    if let errorMessage {
                        GroupInlineError(text: errorMessage)
                    }

                    Button(isCreating ? "Creating…" : "Create group") {
                        Task { await submit() }
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(isCreating)
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Create a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Enter a group name."
            return
        }
        if trimmed.count > GroupHelpers.groupNameMaxLength {
            errorMessage = "Keep the name under \(GroupHelpers.groupNameMaxLength) characters."
            return
        }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            try await onCreate(trimmed)
            dismiss()
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't create the group. Try again.")
        }
    }
}

/// "Join a group" sheet with a live-normalized invite code field.
struct JoinGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Joins with the normalized code; throws so the sheet can show the error.
    let onJoin: (String) async throws -> Void

    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    Text("Ask a group owner for their invite code, then enter it here to join their shared tasks.")
                        .font(.htBody)
                        .foregroundStyle(HTColor.textMuted)

                    GroupFieldLabel(text: "Invite code")
                    TextField("ABCD2345", text: $code)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .htField()
                        .disabled(isJoining)
                        .onChange(of: code) { _, value in
                            let normalized = GroupHelpers.normalizeInviteCode(value)
                            if normalized != value { code = normalized }
                        }
                        .onSubmit { Task { await submit() } }

                    if let errorMessage {
                        GroupInlineError(text: errorMessage)
                    }

                    Button(isJoining ? "Joining…" : "Join group") {
                        Task { await submit() }
                    }
                    .buttonStyle(.htPrimary(fullWidth: true))
                    .disabled(isJoining)
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Join a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isJoining)
                }
            }
            .interactiveDismissDisabled(isJoining)
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        let normalized = GroupHelpers.normalizeInviteCode(code)
        guard GroupHelpers.isValidInviteCode(normalized) else {
            errorMessage = "Invite codes are \(GroupHelpers.inviteCodeLength) letters or digits."
            return
        }

        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            try await onJoin(normalized)
            dismiss()
        } catch {
            errorMessage = GroupHelpers.describeAPIError(error, fallback: "We couldn't join that group. Try again.")
        }
    }
}
