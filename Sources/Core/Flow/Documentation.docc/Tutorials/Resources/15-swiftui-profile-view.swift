import SwiftUI
import FlowUI

// ProfileView independently observes the same StateFlow as HomeView.
// Both views stay in sync automatically, with no environment objects,
// no NotificationCenter, and no delegates.
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
