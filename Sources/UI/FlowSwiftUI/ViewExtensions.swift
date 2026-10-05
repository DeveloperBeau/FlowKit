#if canImport(SwiftUI)
public import SwiftUI
public import FlowCore

extension View {
    /// Collects a cold `Flow` for the view's lifetime. Cancels on disappear.
    public func collecting<T: Sendable>(
        _ flow: Flow<T>,
        priority: TaskPriority = .userInitiated,
        action: @escaping @MainActor (T) -> Void
    ) -> some View {
        modifier(CollectingModifier(flow: flow, priority: priority, action: action))
    }
}

/// Wraps `.task` in a named type so its opaque return type stays inside this
/// module. Returned directly, the release-built opaque type descriptor of the
/// newer `.task(name:priority:...)` overload leaks into client code and fails
/// to link on deployment targets below that overload's availability.
private struct CollectingModifier<T: Sendable>: ViewModifier {
    let flow: Flow<T>
    let priority: TaskPriority
    let action: @MainActor (T) -> Void

    func body(content: Content) -> some View {
        content.task(priority: priority) {
            await _collectFlow(flow, action: action)
        }
    }
}

/// Internal helper that drives the collection loop for `View.collecting`.
/// Extracted so unit tests can exercise the collection logic without a
/// SwiftUI view host. The `.task` modifier wrapper remains a trivial
/// one-line forwarder matching the SwiftUI idiom.
@MainActor
internal func _collectFlow<T: Sendable>(
    _ flow: Flow<T>,
    action: @escaping @MainActor (T) -> Void
) async {
    await flow.collect { value in
        await action(value)
    }
}
#endif
