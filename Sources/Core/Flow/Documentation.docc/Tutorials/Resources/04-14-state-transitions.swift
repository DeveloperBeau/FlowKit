import Testing
import Flow
import FlowTesting

@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("sign-in transitions from loggedOut to loggedIn")
    func signInTransition() async throws {
        let manager = SessionManager()

        try await manager.stateFlow.asFlow().probing { reader in
            // Initial state replayed immediately.
            try await reader.expectValue(.loggedOut)

            // Drive the state machine.
            try await manager.signIn(username: "alice", password: "secret")

            // MutableStateFlow emits the new value to all collectors.
            let state = try await reader.awaitValue()
            if case .loggedIn(let user) = state {
                #expect(user.username == "alice")
            } else {
                Issue.record("expected loggedIn but got \(state)")
            }
        }
    }
}
