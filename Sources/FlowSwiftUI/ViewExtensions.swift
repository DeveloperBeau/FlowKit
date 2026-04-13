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
        self.task(priority: priority) {
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
