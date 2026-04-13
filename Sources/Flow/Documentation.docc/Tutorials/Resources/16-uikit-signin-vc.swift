import UIKit
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

// UIKit view controllers use `self.collect(_:action:)` from FlowUIKitBridge.
// The helper ties collection to `flowScope`, which is cancelled automatically
// when the view controller is deallocated — no manual cleanup needed.
final class SignInViewController: UIViewController {
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()

        // Observe session state changes and update the UI on the main actor.
        collect(SessionManager.shared.state) { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: SessionState) {
        switch state {
        case .signedOut:
            statusLabel.text = nil
            signInButton.isEnabled = true
        case .signingIn:
            statusLabel.text = "Signing in…"
            signInButton.isEnabled = false
        case .signedIn(let user):
            statusLabel.text = "Signed in as \(user.name)"
            signInButton.isEnabled = false
        case .error(let message):
            statusLabel.text = message
            signInButton.isEnabled = true
        }
    }

    @objc private func signInTapped() {
        guard let email = emailField.text, let password = passwordField.text else { return }
        Task { await SessionManager.shared.signIn(email: email, password: password) }
    }

    private func setupLayout() {
        signInButton.setTitle("Sign In", for: .normal)
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        // Layout omitted for brevity.
    }
}
