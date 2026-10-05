import Testing
import Flow
import FlowTesting

@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("full sign-in / sign-out lifecycle")
    func fullLifecycle() async throws {
        let manager = SessionManager()

        try await manager.stateFlow.asFlow().probing { reader in
            // Initial state.
            try await reader.expectValue(.loggedOut)

            // Sign in.
            try await manager.signIn(username: "alice", password: "secret")
            try await reader.expectValue(.loggedIn(User(username: "alice")))

            // Sending the same state again must NOT produce a new emission.
            // MutableStateFlow deduplicates consecutive equal values, so the
            // next value read is the sign-out below. A duplicate emission
            // would arrive first and fail the read.
            await manager.stateFlow.send(.loggedIn(User(username: "alice")))

            // Sign out.
            await manager.signOut()
            try await reader.expectNextValue(.loggedOut)
        }
    }
}
