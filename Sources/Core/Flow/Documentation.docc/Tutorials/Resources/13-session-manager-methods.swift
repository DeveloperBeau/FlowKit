import Foundation
import Flow

// A stand-in for your real auth service.
protocol AuthService: Sendable {
    func signIn(email: String, password: String) async throws -> User
    func signOut() async throws
}

@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private let _state = MutableStateFlow<SessionState>(.signedOut)
    var state: any StateFlow<SessionState> { _state }

    private let authService: any AuthService

    // Replace NoOpAuthService with your real AuthService in production.
    // Tests pass their own fake, so the initialiser is not private.
    init(authService: any AuthService = NoOpAuthService()) {
        self.authService = authService
    }

    func signIn(email: String, password: String) async {
        _state.send(.signingIn)
        do {
            let user = try await authService.signIn(email: email, password: password)
            _state.send(.signedIn(user))
        } catch {
            _state.send(.error(error.localizedDescription))
        }
    }

    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            // Best-effort sign-out: clear local state regardless.
        }
        _state.send(.signedOut)
    }
}

struct NoOpAuthService: AuthService {
    func signIn(email: String, password: String) async throws -> User {
        User(id: UUID(), name: "Demo", email: email)
    }
    func signOut() async throws {}
}
