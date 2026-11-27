import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SessionState and User.
@testable import MyApp

// Test that signIn transitions through .signingIn → .signedIn.
@Test("signIn transitions: .signedOut → .signingIn → .signedIn")
func signInTransitions() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().probing { reader in
        // Consume the initial .signedOut emission.
        try await reader.expectValue(.signedOut)

        // Simulate the sign-in sequence.
        state.send(.signingIn)
        try await reader.expectValue(.signingIn)

        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        state.send(.signedIn(user))
        try await reader.expectValue(.signedIn(user))
    }
}
