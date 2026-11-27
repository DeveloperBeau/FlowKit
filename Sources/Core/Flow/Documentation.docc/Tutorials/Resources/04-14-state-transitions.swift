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

    @Test("sign-in transitions from signedOut to signedIn")
    func signInTransition() async throws {
        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        let manager = SessionManager(authService: StubAuthService(user: user))

        try await manager.state.asFlow().probing { reader in
            // Initial state replayed immediately.
            try await reader.expectValue(.signedOut)

            // Drive the state machine.
            await manager.signIn(email: "ada@example.com", password: "secret")

            // MutableStateFlow emits each new value to all collectors, in order.
            try await reader.expectValue(.signingIn)
            try await reader.expectValue(.signedIn(user))
        }
    }
}
