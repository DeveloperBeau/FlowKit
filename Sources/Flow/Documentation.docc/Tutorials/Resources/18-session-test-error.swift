import Testing
import Flow
import FlowTesting

struct User: Sendable, Equatable {
    let id: UUID
    let name: String
    let email: String
}

enum SessionState: Sendable, Equatable {
    case signedOut
    case signingIn
    case signedIn(User)
    case error(String)
}

@Test("signIn transitions: .signedOut → .signingIn → .signedIn")
func signInTransitions() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().test { tester in
        try await tester.expectValue(.signedOut)
        await state.send(.signingIn)
        try await tester.expectValue(.signingIn)
        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        await state.send(.signedIn(user))
        try await tester.expectValue(.signedIn(user))
    }
}

// Test that auth errors are surfaced and recovery returns to .signedOut.
@Test("auth error surfaces as .error and recovers to .signedOut")
func authErrorAndRecovery() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().test { tester in
        try await tester.expectValue(.signedOut)

        // Auth attempt begins
        await state.send(.signingIn)
        try await tester.expectValue(.signingIn)

        // Network error during authentication
        await state.send(.error("Invalid credentials. Please try again."))
        try await tester.expectValue(.error("Invalid credentials. Please try again."))

        // User can retry. State resets to .signedOut first
        await state.send(.signedOut)
        try await tester.expectValue(.signedOut)

        // No further emissions expected
        await tester.expectNoValue(within: .milliseconds(50))
    }
}
