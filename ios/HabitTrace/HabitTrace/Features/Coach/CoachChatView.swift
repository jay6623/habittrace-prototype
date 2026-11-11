import SwiftUI

/// The AI Coach sheet: streamed replies, charts, and confirmable plans.
/// Mirrors `components/coach-chat.tsx`.
struct CoachChatView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CoachChatScreen(taskService: taskService, accessTokenProvider: authManager.validAccessToken)
    }
}

struct CoachChatScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CoachViewModel
    @State private var input = ""
    @State private var reviewDraft: ReviewDraft?
    @FocusState private var inputFocused: Bool

    /// A daily-plan draft opened in the scheduler from "Review & adjust".
    private struct ReviewDraft: Identifiable {
        let id: String
    }

    init(taskService: TaskService?, accessTokenProvider: @escaping CoachViewModel.AccessTokenProvider) {
        _viewModel = StateObject(wrappedValue: CoachViewModel(taskService: taskService, accessTokenProvider: accessTokenProvider))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                messageList
                Divider()
                composer
            }
            .background(HTColor.surfaceMuted)
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.loadHistory() }
            .sheet(item: $reviewDraft) { draft in
                NavigationStack {
                    GenerateDayView(draftID: draft.id)
                        .navigationTitle("Generate day")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { reviewDraft = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: HTSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(HTColor.brand)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Coach")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                Text("AI-powered · uses your tracked data")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }
            Spacer()
            HStack(spacing: HTSpacing.xs) {
                Circle()
                    .fill(viewModel.isStreaming ? HTColor.accentEmerald : HTColor.border)
                    .frame(width: 8, height: 8)
                Text(viewModel.isStreaming ? "Thinking…" : "Ready")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textTertiary)
            }
        }
        .padding(.horizontal, HTSpacing.lg)
        .padding(.vertical, HTSpacing.md)
        .background(HTColor.surface)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HTSpacing.lg) {
                    if viewModel.showsWelcome {
                        welcome
                    }

                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        assistantRow {
                            if viewModel.streamText.isEmpty {
                                TypingDots()
                                    .padding(.vertical, HTSpacing.xs)
                            } else {
                                CoachText(content: viewModel.streamText)
                            }
                        }
                        .id("streaming")
                    }

                    if let error = viewModel.errorMessage {
                        AuthNotice(text: "Error: \(error)", tone: .error)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(HTSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.streamText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            assistantRow {
                Text("Hi! I’m your HabitTrace coach. I can see your task history and patterns. Ask me anything, or tell me what you want to schedule — I’ll add it to your calendar!")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textStrong)
            }
            FlowLayout(spacing: HTSpacing.sm) {
                ForEach(CoachViewModel.suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        Task { await viewModel.send(suggestion) }
                    }
                    .buttonStyle(.htChip(isSelected: false))
                    .multilineTextAlignment(.leading)
                }
            }
            .padding(.leading, 44)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: CoachMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .font(.htBody)
                    .foregroundStyle(.white)
                    .padding(HTSpacing.md)
                    .background(HTColor.brand)
                    .clipShape(.rect(cornerRadii: .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 4), style: .continuous))
            }
        case .assistant:
            assistantRow {
                VStack(alignment: .leading, spacing: HTSpacing.sm) {
                    CoachText(content: message.content)
                    if let chart = message.chart {
                        CoachChartView(spec: chart)
                    }
                }
            } below: {
                if let proposal = message.proposal, message.proposalStatus == .pending {
                    switch proposal {
                    case .task(let taskProposal):
                        TaskConfirmCard(
                            proposal: taskProposal,
                            isBusy: viewModel.busyProposalMessageID == message.id,
                            onConfirm: { start, draft in
                                await viewModel.confirmTask(messageID: message.id, proposal: taskProposal, candidateStart: start, draft: draft)
                            },
                            onCancel: {
                                await viewModel.dismissTask(messageID: message.id, proposal: taskProposal)
                            }
                        )
                    case .dailySchedule(let schedule):
                        DailyScheduleConfirmCard(
                            schedule: schedule,
                            isBusy: viewModel.busyProposalMessageID == message.id,
                            onConfirm: { await viewModel.confirmDailyPlan(messageID: message.id, schedule: schedule) },
                            onCancel: { viewModel.cancelDailyPlan(messageID: message.id) },
                            onReview: { reviewDraft = ReviewDraft(id: schedule.id) }
                        )
                    }
                } else if message.proposalStatus == .confirmed {
                    Label(
                        message.proposal.map { if case .dailySchedule = $0 { return "Daily plan added to schedule" } else { return "Task added to schedule" } } ?? "Added",
                        systemImage: "checkmark"
                    )
                    .font(.htCaption)
                    .foregroundStyle(HTColor.success600)
                } else if message.proposalStatus == .cancelled {
                    Text("Cancelled")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textTertiary)
                }
            }
        }
    }

    private func assistantRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        assistantRow(content: content) { EmptyView() }
    }

    private func assistantRow<Content: View, Below: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder below: () -> Below
    ) -> some View {
        HStack(alignment: .top, spacing: HTSpacing.sm) {
            Text("AI")
                .font(.htEyebrow)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(HTColor.brand)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HTSpacing.md)
                    .background(HTColor.surface)
                    .clipShape(.rect(cornerRadii: .init(topLeading: 4, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16), style: .continuous))
                    .overlay {
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16), style: .continuous)
                            .strokeBorder(HTColor.border, lineWidth: 1)
                    }
                below()
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: HTSpacing.sm) {
            HStack(spacing: HTSpacing.sm) {
                TextField("Ask or schedule a task…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .htField()
                    .submitLabel(.send)
                    .onSubmit { submit() }

                Button {
                    submit()
                } label: {
                    if viewModel.isStreaming {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.htPrimary)
                .disabled(viewModel.isStreaming || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !viewModel.messages.isEmpty {
                Button("Clear conversation") {
                    Task { await viewModel.clearConversation() }
                }
                .font(.htCaption)
                .foregroundStyle(HTColor.textTertiary)
                .disabled(viewModel.isStreaming)
            }
        }
        .padding(HTSpacing.md)
        .background(HTColor.surface)
    }

    private func submit() {
        let text = input
        input = ""
        inputFocused = true
        Task { await viewModel.send(text) }
    }
}

// MARK: - Pieces

/// Assistant text with the PWA's markdown-lite (**bold** and line breaks).
struct CoachText: View {
    let content: String

    var body: some View {
        Text(attributed)
            .font(.htBody)
            .foregroundStyle(HTColor.textStrong)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }
}

struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(HTColor.borderStrong)
                    .frame(width: 8, height: 8)
                    .offset(y: phase == index ? -4 : 0)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Coach is thinking")
    }
}

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
