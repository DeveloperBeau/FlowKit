import Foundation
import Testing
import Flow
import FlowTesting
// MyApp is the app target that holds SessionState and User.
@testable import MyApp

@Test("signIn transitions: .signedOut → .signingIn → .signedIn")
func signInTransitions() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().probing { reader in
        try await reader.expectValue(.signedOut)
        state.send(.signingIn)
        try await reader.expectValue(.signingIn)
        let user = User(id: UUID(), name: "Ada", email: "ada@example.com")
        state.send(.signedIn(user))
        try await reader.expectValue(.signedIn(user))
    }
}

// Test that auth errors are surfaced and recovery returns to .signedOut.
@Test("auth error surfaces as .error and recovers to .signedOut")
func authErrorAndRecovery() async throws {
    let state = MutableStateFlow<SessionState>(.signedOut)

    try await state.asFlow().probing { reader in
        try await reader.expectValue(.signedOut)

        // Auth attempt begins
        state.send(.signingIn)
        try await reader.expectValue(.signingIn)

        // Network error during authentication
        state.send(.error("Invalid credentials. Please try again."))
        try await reader.expectValue(.error("Invalid credentials. Please try again."))

        // User can retry. State resets to .signedOut first
        state.send(.signedOut)
        try await reader.expectValue(.signedOut)

        // Nothing else arrived in between: the next value is the one we send.
        state.send(.signingIn)
        try await reader.expectNextValue(.signingIn)
    }
}
