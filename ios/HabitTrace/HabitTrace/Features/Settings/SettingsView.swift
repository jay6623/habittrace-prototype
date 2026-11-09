import SwiftUI
import PhotosUI

/// Settings tab entry: resolves the auth manager and hosts the screen.
struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        SettingsScreen(authManager: authManager)
    }
}

/// "Your preferences": profile & planning, connected calendars, records
/// export, password & security, and sign out.
struct SettingsScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel: SettingsViewModel

    @State private var showingSignOutConfirmation = false
    @State private var avatarSelection: PhotosPickerItem?
    @State private var showingAvatarMenu = false
    @State private var durationText: String

    init(authManager: AuthManager) {
        let model = SettingsViewModel(authManager: authManager)
        _viewModel = StateObject(wrappedValue: model)
        _durationText = State(initialValue: "\(model.preferences.defaultDuration)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HTSpacing.lg) {
                    VStack(alignment: .leading, spacing: HTSpacing.xs) {
                        Text("Your preferences")
                            .htPageTitle()
                        Text("Make planning fit your day.")
                            .font(.htBody)
                            .foregroundStyle(HTColor.textSecondary)
                    }

                    profileCard
                    calendarsCard
                    recordsCard
                    securityCard

                    Button {
                        showingSignOutConfirmation = true
                    } label: {
                        Text(viewModel.isSigningOut ? "Signing out…" : "Sign out")
                            .foregroundStyle(HTColor.danger700)
                    }
                    .buttonStyle(.htSecondary(fullWidth: true))
                    .disabled(viewModel.isBusy || viewModel.isAvatarBusy || viewModel.isSigningOut)
                }
                .padding(.horizontal, HTSpacing.screenHorizontal)
                .padding(.top, HTSpacing.screenTop)
                .padding(.bottom, HTSpacing.screenBottom)
            }
            .background(HTColor.surfaceMuted)
            .toolbar(.hidden, for: .navigationBar)
            .htToast($viewModel.toast)
            .onChange(of: authManager.currentUserID) { _, _ in
                viewModel.reloadFromSession()
                durationText = "\(viewModel.preferences.defaultDuration)"
            }
            .onChange(of: avatarSelection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await viewModel.uploadAvatar(imageData: data)
                    } else {
                        viewModel.toast = .error("Upload failed. Couldn’t read that picture.")
                    }
                    avatarSelection = nil
                }
            }
            .sheet(item: $viewModel.exportFileURL) { url in
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await viewModel.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need to sign in again to see your plans and groups.")
            }
        }
    }

    // MARK: - Profile & planning

    private var profileCard: some View {
        let uploadTitle = viewModel.isAvatarBusy ? "Working…" : "Upload new picture"
        return VStack(alignment: .leading, spacing: HTSpacing.lg) {
            Text("Profile & planning")
                .htSectionTitle()

            HStack(alignment: .center, spacing: HTSpacing.md) {
                Menu {
                    PhotosPicker(selection: $avatarSelection, matching: .images) {
                        Label(uploadTitle, systemImage: "photo")
                    }
                    Button {
                        Task { await viewModel.resetAvatar() }
                    } label: {
                        Label("Set back to default", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.hasCustomAvatar)
                } label: {
                    AvatarView(url: viewModel.avatarURL, initials: viewModel.initials, size: 80)
                        .overlay {
                            if viewModel.isAvatarBusy {
                                ProgressView().tint(.white)
                            }
                        }
                }
                .disabled(viewModel.isAvatarBusy || viewModel.isBusy)
                .accessibilityLabel("Change profile picture")

                Text("Tap your picture to upload a new one or restore the default.")
                    .font(.htBody)
                    .foregroundStyle(HTColor.textMuted)
            }

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                Text("Display name")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textStrong)
                TextField("Your name", text: $viewModel.name)
                    .textContentType(.name)
                    .htField()
                    .onChange(of: viewModel.name) { _, value in
                        if value.count > 80 { viewModel.name = String(value.prefix(80)) }
                    }
                Text("Signed in as \(viewModel.email)")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)
            }

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                Text("Default plan duration (minutes)")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textStrong)
                TextField("30", text: $durationText)
                    .keyboardType(.numberPad)
                    .htField()
                    .onChange(of: durationText) { _, value in
                        let digits = value.filter(\.isNumber)
                        if digits != value { durationText = digits }
                        if let minutes = Int(digits) { viewModel.preferences.defaultDuration = minutes }
                    }
            }

            VStack(alignment: .leading, spacing: HTSpacing.sm) {
                Text("Daily availability")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textStrong)
                Text("Find a time only suggests slots inside this window. You can still add plans outside it manually.")
                    .font(.htCaption)
                    .foregroundStyle(HTColor.textMuted)

                HStack(spacing: HTSpacing.md) {
                    availabilityPicker("From", time: $viewModel.preferences.workStart)
                    availabilityPicker("Until", time: $viewModel.preferences.workEnd)
                }
            }

            Text("Times use your device’s time zone: \(viewModel.timeZoneName).")
                .font(.htCaption)
                .foregroundStyle(HTColor.textMuted)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.htCaption)
                    .foregroundStyle(HTColor.danger700)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button(viewModel.isBusy ? "Working…" : "Save preferences") {
                Task { await viewModel.save() }
            }
            .buttonStyle(.htPrimary)
            .disabled(viewModel.isBusy || viewModel.isAvatarBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htPanel()
    }

    private func availabilityPicker(_ label: String, time: Binding<String>) -> some View {
        let binding = Binding<Date>(
            get: {
                let minutes = PlanningPreferences.minutes(from: time.wrappedValue)
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                time.wrappedValue = PlanningPreferences.time(fromMinutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
        return VStack(alignment: .leading, spacing: HTSpacing.xs) {
            Text(label)
                .font(.htCaptionStrong)
                .foregroundStyle(HTColor.textStrong)
            DatePicker(label, selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Other sections

    private var calendarsCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Connected calendars")
                .htSectionTitle()
            Text("Choose whether to send your plans to Google Calendar. Importing external events is not currently supported.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
            NavigationLink {
                GoogleCalendarView()
            } label: {
                Text("Manage connections")
            }
            .buttonStyle(.htSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htPanel()
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            Text("Your records")
                .htSectionTitle()
            Text("Download your personal plans, execution history and saved profile preferences as JSON. Group and AI research records are not included in this export.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)
            Button(viewModel.isBusy ? "Working…" : "Download records") {
                Task { await viewModel.exportRecords() }
            }
            .buttonStyle(.htSecondary)
            .disabled(viewModel.isBusy || viewModel.isAvatarBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htPanel()
    }

    private var securityCard: some View {
        NavigationLink {
            PasswordSecurityView()
        } label: {
            HStack {
                Text("Password & security")
                    .font(.htBodyStrong)
                    .foregroundStyle(HTColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HTColor.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: HTControlHeight.prominent)
            .padding(.horizontal, HTSpacing.lg)
            .background(HTColor.surface)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HTRadius.lg, style: .continuous)
                    .strokeBorder(HTColor.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// Circular avatar: remote image when available, otherwise initials on ink.
struct AvatarView: View {
    let url: URL?
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(HTColor.ink)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(HTColor.border, lineWidth: 2) }
    }

    private var initialsText: some View {
        Text(initials)
            .font(.system(size: size * 0.32, weight: .bold))
            .foregroundStyle(.white)
    }
}

/// PWA `.field`: slate-100 background, 16pt radius, 48pt tall.
struct HTFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.htBody)
            .padding(.horizontal, HTSpacing.lg)
            .frame(minHeight: HTControlHeight.prominent - 8)
            .background(HTColor.surfaceSecondary)
            .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
    }
}

extension View {
    func htField() -> some View {
        modifier(HTFieldModifier())
    }
}

/// System share sheet for the exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
