import SwiftUI
import UIKit

/// Groups tab entry. Rebuilt when the signed-in account changes so the
/// remembered selection and the detail belong to the current user.
struct GroupsView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        GroupsScreen(
            currentUserID: authManager.currentUserID,
            accessTokenProvider: authManager.validAccessToken
        )
        .id(authManager.currentUserID)
    }
}

/// Sections of the selected group's detail.
enum GroupDetailTab: String, CaseIterable, Identifiable {
    case tasks
    case members
    case overview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .members: "Members"
        case .overview: "Overview"
        }
    }
}

/// Identifies the announcement whose thread sheet is open.
private struct GroupThreadTarget: Identifiable {
    let id: String
}

/// Group Scheduling: the member's groups, invite code, shared tasks,
/// members, announcements, and personal planning. Mirrors `/dashboard/group`.
struct GroupsScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService
    @StateObject private var viewModel: GroupsViewModel

    @State private var selectedTab: GroupDetailTab = .tasks
    @State private var setupSheet: GroupSetupSheet?
    @State private var isShowingTaskForm = false
    @State private var personalPlanTask: GroupTask?
    @State private var copyRequest: PlanFormRequest?
    @State private var threadTarget: GroupThreadTarget?
    @State private var taskPendingDeletion: GroupTask?
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false
    @State private var didCopyInvite = false

    init(currentUserID: String?, accessTokenProvider: @escaping GroupsViewModel.AccessTokenProvider) {
        _viewModel = StateObject(
            wrappedValue: GroupsViewModel(currentUserID: currentUserID, accessTokenProvider: accessTokenProvider)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.md) {
                    header
                    content
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.lg)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .htToast($viewModel.toast)
            .task { await viewModel.loadGroups() }
            .refreshable { await viewModel.loadGroups() }
            .sheet(item: $setupSheet) { sheet in
                switch sheet {
                case .create:
                    CreateGroupSheet { name in
                        try await viewModel.createGroup(name: name)
                    }
                case .join:
                    JoinGroupSheet { code in
                        try await viewModel.joinGroup(inviteCode: code)
                    }
                }
            }
            .sheet(isPresented: $isShowingTaskForm) {
                GroupTaskFormSheet(
                    members: viewModel.members,
                    timeZone: viewModel.timeZone,
                    memberName: { viewModel.memberName($0) }
                ) { input in
                    try await viewModel.createTask(input)
                }
            }
            .sheet(item: $personalPlanTask) { task in
                GroupPersonalPlanSheet(
                    task: task,
                    timeZone: viewModel.timeZone,
                    preview: { input in try await viewModel.previewPersonalPlan(for: task, input: input) },
                    confirm: { input in try await viewModel.confirmPersonalPlan(for: task, input: input) }
                )
            }
            .sheet(item: $copyRequest) { request in
                PlanFormSheet(
                    request: request,
                    actions: .creating(with: taskService, accessToken: authManager.validAccessToken)
                ) { _ in
                    viewModel.personalCopyCreated()
                }
            }
            .sheet(item: $threadTarget) { target in
                GroupAnnouncementThreadSheet(viewModel: viewModel, announcementID: target.id)
            }
            .confirmationDialog(
                "Delete for everyone?",
                isPresented: isConfirmingTaskDeletion,
                titleVisibility: .visible,
                presenting: taskPendingDeletion
            ) { task in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteTask(task) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { task in
                Text("“\(task.title)” will be permanently removed for every member.")
            }
            .confirmationDialog("Leave this group?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task { await viewModel.leaveSelectedGroup() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will no longer be able to see this group or its tasks.")
            }
            .confirmationDialog("Delete for everyone?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteSelectedGroup() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This group and its shared tasks will be permanently removed for every member.")
            }
        }
    }

    private var isConfirmingTaskDeletion: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { if !$0 { taskPendingDeletion = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HTEyebrowLabel(text: "Group Scheduling")
                Text(viewModel.selectedGroup?.name ?? "Your groups")
                    .htPageTitle()
                    .lineLimit(2)
            }

            HStack(spacing: HTSpacing.sm) {
                Button("Invite member") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.isShowingInvite.toggle()
                    }
                }
                .buttonStyle(.htSecondary(fullWidth: true))
                .disabled(viewModel.selectedGroup == nil)

                Button("+ Add group task") {
                    isShowingTaskForm = true
                }
                .buttonStyle(.htPrimary(fullWidth: true))
                .disabled(viewModel.activeDetail == nil)
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingGroups, viewModel.groups.isEmpty {
            loadingPanel("Loading your groups…")
        } else if let message = viewModel.groupsError, viewModel.groups.isEmpty {
            errorPanel(message) {
                Task { await viewModel.loadGroups() }
            }
        } else if viewModel.groups.isEmpty {
            GroupSetupEmptyView(
                onCreate: { setupSheet = .create },
                onJoin: { setupSheet = .join }
            )
            .padding(.top, HTSpacing.sm)
        } else {
            groupPicker

            if viewModel.isShowingSetup {
                GroupSetupPanel(
                    onCreate: { setupSheet = .create },
                    onJoin: { setupSheet = .join },
                    onDismiss: { viewModel.isShowingSetup = false }
                )
            }

            if viewModel.isShowingInvite, let group = viewModel.selectedGroup {
                invitePanel(group)
            }

            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let message = viewModel.detailError {
            errorPanel(message) {
                Task { await viewModel.reloadDetail() }
            }
        } else if viewModel.isLoadingDetail, viewModel.activeDetail == nil {
            loadingPanel("Loading \(viewModel.selectedGroup?.name ?? "group")…")
        } else if let detail = viewModel.activeDetail {
            statsGrid(detail)

            GroupAnnouncementsCard(viewModel: viewModel) { announcement in
                threadTarget = GroupThreadTarget(id: announcement.id)
            }

            Picker("Section", selection: $selectedTab) {
                ForEach(GroupDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .tasks:
                GroupTasksTab(
                    viewModel: viewModel,
                    onAddTask: { isShowingTaskForm = true },
                    onPlan: { personalPlanTask = $0 },
                    onCopy: { task in
                        copyRequest = PlanFormRequest(
                            draft: GroupsViewModel.copyDraft(for: task),
                            editingTaskID: nil
                        )
                    },
                    onDelete: { taskPendingDeletion = $0 }
                )
            case .members:
                GroupMembersTab(viewModel: viewModel) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.isShowingInvite = true
                    }
                }
            case .overview:
                GroupOverviewTab(
                    viewModel: viewModel,
                    onLeave: { isConfirmingLeave = true },
                    onDelete: { isConfirmingDelete = true }
                )
            }
        }
    }

    private func loadingPanel(_ text: String) -> some View {
        Text(text)
            .font(.htBody)
            .foregroundStyle(HTColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .htPanel()
    }

    private func errorPanel(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            AuthNotice(text: message, tone: .error)
            Button("Retry", action: retry)
                .buttonStyle(.htSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    // MARK: - Group picker

    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HTSpacing.sm) {
                ForEach(viewModel.groups) { group in
                    let isSelected = group.id == viewModel.selectedGroupID
                    Button {
                        Task { await viewModel.select(groupID: group.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.name)
                                .font(.htCaptionStrong)
                                .lineLimit(1)
                            Text(group.role.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundStyle(isSelected ? .white : HTColor.textStrong)
                        .padding(.horizontal, HTSpacing.md)
                        .padding(.vertical, HTSpacing.sm)
                        .background(isSelected ? HTColor.brand : HTColor.surface)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(isSelected ? HTColor.brand : HTColor.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.name), \(group.role.rawValue)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }

                Button("New / Join") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.isShowingSetup.toggle()
                    }
                }
                .buttonStyle(.htChip(isSelected: viewModel.isShowingSetup))
                .accessibilityAddTraits(viewModel.isShowingSetup ? [.isSelected] : [])
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: - Invite panel

    private func invitePanel(_ group: GroupResponse) -> some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            Text("Invite to \(group.name)")
                .font(.htCardTitle)
                .foregroundStyle(HTColor.textPrimary)
            Text("Share this code with teammates — they can join from their HabitTrace account using \"New / Join\".")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)

            HStack(spacing: HTSpacing.sm) {
                Text(group.inviteCode)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(HTColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, HTSpacing.md)
                    .padding(.vertical, HTSpacing.sm)
                    .background(HTColor.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))
                Spacer(minLength: HTSpacing.sm)
                Button(didCopyInvite ? "Copied ✓" : "Copy") {
                    copyInviteCode(group.inviteCode)
                }
                .buttonStyle(.htSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        didCopyInvite = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyInvite = false
        }
    }

    // MARK: - Stats

    private func statsGrid(_ detail: GroupDetail) -> some View {
        let stats = viewModel.stats
        let total = stats.loggedCount > 0 ? stats.loggedCount : detail.tasks.count
        var tasksCaption = "\(stats.done) completed"
        if stats.failed > 0 {
            tasksCaption += " · \(stats.failed) not completed"
        }

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: HTSpacing.sm), GridItem(.flexible(), spacing: HTSpacing.sm)],
            spacing: HTSpacing.sm
        ) {
            HTStatTile(title: "Group success rate", value: stats.successRate.map { "\($0)%" } ?? "—")
            HTStatTile(title: "Group tasks", value: "\(stats.done) / \(total)", caption: tasksCaption)
            HTStatTile(title: "Members", value: "\(detail.members.count)", caption: "You are the \(detail.group.role.rawValue)")
            HTStatTile(title: "Assigned to you", value: "\(stats.assignedToMeUnlogged)", caption: "not logged")
        }
    }
}
