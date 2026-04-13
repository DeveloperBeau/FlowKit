import Testing
import Flow
import FlowTesting

@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("sign-in transitions from loggedOut to loggedIn")
    func signInTransition() async throws {
        let manager = SessionManager()

        try await TestScope.run { scope in
            let tester = try await scope.test(manager.stateFlow.asFlow())

            // Initial state replayed immediately.
            try await tester.expectValue(.loggedOut)

            // Drive the state machine.
            try await manager.signIn(username: "alice", password: "secret")

            // MutableStateFlow emits the new value to all collectors.
            let state = try await tester.awaitValue()
            if case .loggedIn(let user) = state {
                #expect(user.username == "alice")
            } else {
                Issue.record("expected loggedIn but got \(state)")
            }
        }
    }
}
