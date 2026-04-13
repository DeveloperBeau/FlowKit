#if canImport(SwiftUI)
public import SwiftUI
public import FlowHotStreams

/// A property wrapper that collects a `StateFlow` and makes its current
/// value available as a SwiftUI binding. Supports optional animation or
/// transaction wrapping for updates.
///
/// ## Example
///
/// ```swift
/// struct ProfileView: View {
///     @CollectedState(SessionManager.shared.sessionState)
///     var session: SessionState = .signedOut
///
///     var body: some View {
///         switch session {
///         case .signedIn(let user): Text("Hello, \(user.name)")
///         case .signedOut: Text("Please sign in")
///         case .signingIn: ProgressView()
///         case .error(let msg): Text(msg)
///         }
///     }
/// }
/// ```
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
@propertyWrapper
@MainActor
public struct CollectedState<Element: Sendable & Equatable>: DynamicProperty {
    @State private var observed: ObservedStateFlow<Element>

    public init(
        wrappedValue initialValue: Element,
        _ source: @autoclosure () -> any StateFlow<Element>,
        animation: Animation? = nil
    ) {
        let policy: ObservedStateFlow<Element>.UpdatePolicy = if let animation {
            .animated(animation)
        } else {
            .immediate
        }
        _observed = State(initialValue: ObservedStateFlow(
            source(), initialValue: initialValue, updatePolicy: policy
        ))
    }

    public var wrappedValue: Element { observed.value }

    public func update() { observed.start() }
}
#endif
