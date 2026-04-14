import SwiftUI
import Flow

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

// HomeView uses @CollectedState to observe SessionManager.shared.state.
// When the state changes anywhere in the app (after sign-in, sign-out,
// or an auth error), SwiftUI automatically re-renders this view.
struct HomeView: View {
    @CollectedState(SessionManager.shared.state) var session: SessionState = .signedOut

    var body: some View {
        switch session {
        case .signedOut:
            Text("You are signed out.")
        case .signingIn:
            ProgressView("Signing in…")
        case .signedIn(let user):
            VStack(spacing: 12) {
                Text("Welcome back, \(user.name)!")
                    .font(.title2)
                Button("Sign out") {
                    Task { await SessionManager.shared.signOut() }
                }
            }
        case .error(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}
