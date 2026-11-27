import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SessionManager and SessionState.
@testable import MyApp

// A fake auth service that always rejects the credentials.
struct RejectingAuthService: AuthService {
    struct BadCredentials: LocalizedError {
        var errorDescription: String? { "Invalid credentials." }
    }

    func signIn(email: String, password: String) async throws -> User {
        throw BadCredentials()
    }
    func signOut() async throws {}
}

@MainActor
@Suite("SessionManager error paths")
struct SessionManagerErrorTests {

    @Test("signIn ends in .error on bad credentials")
    func signInEndsInErrorOnBadCredentials() async {
        let manager = SessionManager(authService: RejectingAuthService())

        // signIn does not throw. It reports the failure as a state.
        await manager.signIn(email: "ada@example.com", password: "wrong")

        // Read the current state without collecting the flow at all.
        #expect(manager.state.value == .error("Invalid credentials."))
    }
}
