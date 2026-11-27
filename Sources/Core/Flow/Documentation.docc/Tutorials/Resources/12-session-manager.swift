import Flow

// SessionManager is the single source of truth for authentication state.
// Any view or component that needs to react to sign-in / sign-out gets its
// own independent observation without any manual notification plumbing.
@MainActor
final class SessionManager {
    static let shared = SessionManager()

    // MutableStateFlow holds the current state and broadcasts every change
    // to all active subscribers: SwiftUI views, UIKit controllers, and tests.
    private let _state = MutableStateFlow<SessionState>(.signedOut)

    // Expose a read-only StateFlow so callers cannot mutate state directly.
    var state: any StateFlow<SessionState> { _state }

    init() {}
}
