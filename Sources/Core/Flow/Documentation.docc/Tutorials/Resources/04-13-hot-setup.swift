import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SessionManager, SessionState and User.
@testable import MyApp

// A fake auth service that signs in as a fixed user.
struct StubAuthService: AuthService {
    let user: User

    func signIn(email: String, password: String) async throws -> User { user }
    func signOut() async throws {}
}

@MainActor
@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("initial state is signedOut")
    func initialStateIsSignedOut() async throws {
        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        let manager = SessionManager(authService: StubAuthService(user: user))

        // MutableStateFlow replays its current value to each new collector,
        // so the first expectValue call sees the initial state immediately.
        try await manager.state.asFlow().probing { reader in
            try await reader.expectValue(.signedOut)

            // Assertions for transitions continue in the next step.
        }
    }
}
