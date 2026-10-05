import Foundation
import Combine
import Supabase
import Auth

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private let client = SupabaseProvider.client
    private var authTask: Task<Void, Never>?

    init() {
        observeAuthState()
    }

    deinit {
        authTask?.cancel()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var accessToken: String? {
        session?.accessToken
    }
    
    func validAccessToken() async throws -> String {
        let currentSession = try await client.auth.session
        session = currentSession
        return currentSession.accessToken
    }

    var currentUserEmail: String? {
        session?.user.email
    }

    func signIn(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )

            self.session = session
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() async {
        errorMessage = nil

        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeAuthState() {
        authTask = Task { [weak self] in
            guard let self else { return }

            for await (_, session) in client.auth.authStateChanges {
                self.session = session
                self.isLoading = false
            }
        }
    }
}
