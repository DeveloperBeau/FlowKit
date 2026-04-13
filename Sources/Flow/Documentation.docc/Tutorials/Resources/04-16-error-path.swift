import Testing
import Flow
import FlowTesting

@Suite("SessionManager error paths")
struct SessionManagerErrorTests {

    @Test("signIn throws on bad credentials")
    func signInThrowsOnBadCredentials() async throws {
        let manager = SessionManager()

        // signIn throws AuthError.badCredentials when credentials are wrong.
        // We collect stateFlow as a ThrowingFlow by mapping through mapThrowing
        // so that the thrown error surfaces via ThrowingFlowTester.
        let throwingFlow = manager.stateFlow.asFlow().mapThrowing { state in
            state   // passthrough — errors come from signIn, tested separately
        }

        // Test the signIn throw directly without collecting stateFlow.
        await #expect(throws: AuthError.badCredentials) {
            try await manager.signIn(username: "alice", password: "wrong")
        }

        // Confirm the state remains .loggedOut after the failed sign-in.
        #expect(await manager.stateFlow.value == .loggedOut)
    }
}
