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
                Button("Sign out") {
                    Task { await SessionManager.shared.signOut() }
                }
            }
        case .error(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

// ProfileView independently observes the same StateFlow.
// Both HomeView and ProfileView stay in sync automatically, with no
// environment objects, no NotificationCenter, and no delegates.
struct ProfileView: View {
    @CollectedState(SessionManager.shared.state) var session: SessionState = .signedOut

    var body: some View {
        Group {
            if case .signedIn(let user) = session {
                Form {
                    Section("Account") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                    }
                }
                .navigationTitle("Profile")
            } else {
                ContentUnavailableView(
                    "Not signed in",
                    systemImage: "person.slash"
                )
            }
        }
    }
}
