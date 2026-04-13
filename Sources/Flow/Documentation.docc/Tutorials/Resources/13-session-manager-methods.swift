import Foundation
import Flow

struct User: Sendable, Equatable {
    let id: UUID
    let name: String
    let email: String
}

enum SessionState: Sendable, Equatable {
    case signedOut
    case signingIn
    case signedIn(User)
    case error(String)
}

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

    private var authService: any AuthService

    private init() {
        // Replace with your real AuthService in production.
        self.authService = NoOpAuthService()
    }

    func signIn(email: String, password: String) async {
        await _state.send(.signingIn)
        do {
            let user = try await authService.signIn(email: email, password: password)
            await _state.send(.signedIn(user))
        } catch {
            await _state.send(.error(error.localizedDescription))
        }
    }

    func signOut() async {
        do {
            try await authService.signOut()
        } catch {
            // Best-effort sign-out: clear local state regardless.
        }
        await _state.send(.signedOut)
    }
}

private struct NoOpAuthService: AuthService {
    func signIn(email: String, password: String) async throws -> User {
        User(id: UUID(), name: "Demo", email: email)
    }
    func signOut() async throws {}
}
