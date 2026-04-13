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

// Test that signIn transitions through .signingIn → .signedIn.
@Test("signIn transitions: .signedOut → .signingIn → .signedIn")
func signInTransitions() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().test { tester in
        // Consume the initial .signedOut emission.
        try await tester.expectValue(.signedOut)

        // Simulate the sign-in sequence.
        await state.send(.signingIn)
        try await tester.expectValue(.signingIn)

        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        await state.send(.signedIn(user))
        try await tester.expectValue(.signedIn(user))
    }
}
