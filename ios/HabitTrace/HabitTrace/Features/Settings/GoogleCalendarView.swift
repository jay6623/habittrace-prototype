import SwiftUI

/// "Connected Apps": Google Calendar status, connect, sync, disconnect.
/// Mirrors the PWA's `/dashboard/integrations`, limited to the one
/// integration that exists on the backend.
struct GoogleCalendarView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var status: GoogleCalendarStatus?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var notice: String?
    @State private var errorMessage: String?

    private let apiClient = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HTSpacing.lg) {
                VStack(alignment: .leading, spacing: HTSpacing.xs) {
                    HTEyebrowLabel(text: "Integrations")
                    Text("Connected Apps")
                        .htPageTitle()
                }

                if let notice {
                    Text(notice)
                        .font(.htBody)
                        .foregroundStyle(HTColor.success700)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(HTSpacing.md)
                        .background(HTColor.success50)
                        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.htBody)
                        .foregroundStyle(HTColor.danger700)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(HTSpacing.md)
                        .background(HTColor.danger50)
                        .clipShape(.rect(cornerRadius: HTRadius.lg, style: .continuous))
                }

                card
            }
            .padding(.horizontal, HTSpacing.screenHorizontal)
            .padding(.vertical, HTSpacing.lg)
        }
        .background(HTColor.surfaceMuted)
        .navigationTitle("Connected calendars")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
        .refreshable { await loadStatus() }
    }

    private var isConnected: Bool { status?.connected ?? false }
    private var isConfigured: Bool { status?.configured ?? true }

    private var card: some View {
        VStack(alignment: .leading, spacing: HTSpacing.md) {
            HStack(alignment: .top, spacing: HTSpacing.md) {
                Text("📅")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(HTColor.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: HTRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: HTSpacing.xs) {
                        Text("Google Calendar")
                            .font(.htCardTitle)
                            .foregroundStyle(HTColor.textPrimary)
                        if isConnected {
                            Text("Connected")
                                .font(.htCaption)
                                .foregroundStyle(HTColor.success700)
                                .padding(.horizontal, HTSpacing.sm)
                                .padding(.vertical, 2)
                                .background(HTColor.success100)
                                .clipShape(Capsule())
                        }
                    }
                    Text("Calendar")
                        .font(.htCaption)
                        .foregroundStyle(HTColor.textTertiary)
                }
            }

            Text("Sync tasks with your Google Calendar. Tasks appear as calendar events automatically.")
                .font(.htBody)
                .foregroundStyle(HTColor.textMuted)

            if let status, status.connected {
                if let synced = status.lastSyncedAt, let date = TaskTimeFormatting.date(fromISO8601: synced) {
                    HTMetaText("Last synced \(TaskTimeFormatting.shortDateTime(date))", status.timezone ?? "")
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Button(primaryTitle) {
                    Task { await toggleConnection() }
                }
                .buttonStyle(.htPrimary(fullWidth: true))
                .disabled(isWorking || (!isConfigured && !isConnected))

                if isConnected {
                    Button("Sync now") {
                        Task { await sync() }
                    }
                    .buttonStyle(.htSecondary(fullWidth: true))
                    .disabled(isWorking)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .htCard()
    }

    private var primaryTitle: String {
        if isWorking { return "Connecting…" }
        if !isConfigured && !isConnected { return "Backend setup required" }
        return isConnected ? "Disconnect" : "Connect"
    }

    // MARK: - Actions

    private func loadStatus() async {
        isLoading = status == nil
        defer { isLoading = false }
        do {
            let token = try await authManager.validAccessToken()
            let loaded = try await apiClient.fetchGoogleCalendarStatus(accessToken: token)
            status = loaded
            if let lastError = loaded.lastError, !lastError.isEmpty {
                errorMessage = lastError
            }
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func toggleConnection() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }

        do {
            let token = try await authManager.validAccessToken()
            if isConnected {
                try await apiClient.disconnectGoogleCalendar(accessToken: token)
                status?.connected = false
                notice = "Google Calendar disconnected. Existing Google events were left unchanged."
                return
            }
            guard isConfigured else {
                throw GoogleCalendarViewError.notConfigured
            }

            let grant = try await authManager.authorizeGoogleCalendar()
            let freshToken = try await authManager.validAccessToken()
            let result = try await apiClient.connectGoogleCalendar(
                accessToken: freshToken,
                providerToken: grant.providerToken,
                providerRefreshToken: grant.providerRefreshToken,
                timezone: TimeZone.current.identifier
            )
            status = result.status
            notice = "Google Calendar connected. \(result.sync.synced) task\(result.sync.synced == 1 ? "" : "s") synced."
        } catch where AuthManager.isUserCancellation(error) {
            // The user closed the Google sheet; nothing to report.
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func sync() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        notice = nil
        defer { isWorking = false }

        do {
            let token = try await authManager.validAccessToken()
            let result = try await apiClient.syncGoogleCalendar(accessToken: token)
            notice = "\(result.synced) task\(result.synced == 1 ? "" : "s") synced to Google Calendar."
            if result.failed > 0 {
                errorMessage = "\(result.failed) task\(result.failed == 1 ? "" : "s") could not be synced."
            }
            await loadStatus()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private enum GoogleCalendarViewError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "Google Calendar environment variables are missing on the backend."
    }
}
