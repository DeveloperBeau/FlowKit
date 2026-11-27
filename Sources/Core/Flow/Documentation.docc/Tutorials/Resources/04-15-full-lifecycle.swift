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

    @Test("full sign-in / sign-out lifecycle")
    func fullLifecycle() async throws {
        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        let manager = SessionManager(authService: StubAuthService(user: user))

        try await manager.state.asFlow().probing { reader in
            // Initial state.
            try await reader.expectValue(.signedOut)

            // Sign in.
            await manager.signIn(email: "ada@example.com", password: "secret")
            try await reader.expectValue(.signingIn)
            try await reader.expectValue(.signedIn(user))

            // Sign out twice. The second call sets .signedOut again.
            // MutableStateFlow drops a value equal to the current one, so
            // the reader sees only one .signedOut.
            await manager.signOut()
            await manager.signOut()
            try await reader.expectValue(.signedOut)

            // The next value is the sign-in below. A duplicate .signedOut
            // would have arrived first, and this read would fail.
            await manager.signIn(email: "ada@example.com", password: "secret")
            try await reader.expectNextValue(.signingIn)
        }
    }
}
