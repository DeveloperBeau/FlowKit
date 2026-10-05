import Testing
import Flow
import FlowTesting

@Suite("SessionManager error paths")
struct SessionManagerErrorTests {

    @Test("signIn throws on bad credentials")
    func signInThrowsOnBadCredentials() async throws {
        let manager = SessionManager()

        // signIn throws AuthError.badCredentials when credentials are wrong.
        // Test the signIn throw directly without collecting stateFlow.
        await #expect(throws: AuthError.badCredentials) {
            try await manager.signIn(username: "alice", password: "wrong")
        }

        // Confirm the state remains .loggedOut after the failed sign-in.
        #expect(await manager.stateFlow.value == .loggedOut)
    }
}
