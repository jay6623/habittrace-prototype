import Foundation

/// `GET /integrations/google-calendar/status`.
nonisolated struct GoogleCalendarStatus: Decodable, Equatable, Sendable {
    var configured: Bool
    var connected: Bool
    var timezone: String?
    var lastSyncedAt: String?
    var lastError: String?
}

/// `POST /integrations/google-calendar/sync`.
nonisolated struct GoogleCalendarSyncResult: Decodable, Equatable, Sendable {
    var synced: Int
    var failed: Int
    var errors: [String]
}

/// `POST /integrations/google-calendar/connect`.
nonisolated struct GoogleCalendarConnectResult: Decodable, Equatable, Sendable {
    var status: GoogleCalendarStatus
    var sync: GoogleCalendarSyncResult
}

extension APIClient {
    // MARK: - Account

    /// `GET /account/export`: the signed-in user's tasks and executions as
    /// raw JSON. Returned undecoded so the export file keeps every field.
    func exportAccount(accessToken: String) async throws -> Data {
        let request = try makeRequest(.get, path: "account/export", accessToken: accessToken)
        return try await perform(request)
    }

    // MARK: - Google Calendar

    func fetchGoogleCalendarStatus(accessToken: String) async throws -> GoogleCalendarStatus {
        let request = try makeRequest(.get, path: "integrations/google-calendar/status", accessToken: accessToken)
        return try await send(request)
    }

    /// Stores the Google tokens server-side and runs a first sync. 422 with
    /// a `detail` message when Google rejects the token.
    func connectGoogleCalendar(
        accessToken: String,
        providerToken: String,
        providerRefreshToken: String?,
        timezone: String
    ) async throws -> GoogleCalendarConnectResult {
        let body = GoogleCalendarConnectRequest(
            providerToken: providerToken,
            providerRefreshToken: providerRefreshToken,
            timezone: timezone
        )
        let request = try makeRequest(
            .post,
            path: "integrations/google-calendar/connect",
            body: body,
            accessToken: accessToken
        )
        return try await send(request)
    }

    func syncGoogleCalendar(accessToken: String) async throws -> GoogleCalendarSyncResult {
        var request = try makeRequest(.post, path: "integrations/google-calendar/sync", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    /// `DELETE /integrations/google-calendar`. Existing Google events are
    /// left in place by the server.
    func disconnectGoogleCalendar(accessToken: String) async throws {
        let request = try makeRequest(.delete, path: "integrations/google-calendar", accessToken: accessToken)
        _ = try await perform(request)
    }

    private struct GoogleCalendarConnectRequest: Encodable {
        let providerToken: String
        let providerRefreshToken: String?
        let timezone: String
    }
}
