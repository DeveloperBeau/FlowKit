import Testing
import Flow
import FlowTesting

@Suite("SessionManager state transitions")
struct SessionManagerTests {

    @Test("full sign-in / sign-out lifecycle")
    func fullLifecycle() async throws {
        let manager = SessionManager()

        try await TestScope.run { scope in
            let tester = try await scope.test(manager.stateFlow.asFlow())

            // Initial state.
            try await tester.expectValue(.loggedOut)

            // Sign in.
            try await manager.signIn(username: "alice", password: "secret")
            try await tester.expectValue(.loggedIn(User(username: "alice")))

            // Sending the same state again must NOT produce a new emission —
            // MutableStateFlow deduplicates consecutive equal values.
            await manager.stateFlow.send(.loggedIn(User(username: "alice")))
            await tester.expectNoValue(within: .milliseconds(100))

            // Sign out.
            await manager.signOut()
            try await tester.expectValue(.loggedOut)
        }
    }
}
