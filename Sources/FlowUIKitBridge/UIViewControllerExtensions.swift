#if canImport(UIKit) && !os(watchOS)
import UIKit
import ObjectiveC
import FlowCore
import FlowHotStreams

private var flowScopeKey: UInt8 = 0

extension UIViewController {
    /// A `FlowScope` tied to this view controller's lifetime. Created
    /// lazily on first access. Cancelled automatically when the view
    /// controller is deallocated (because the associated object is released).
    public var flowScope: FlowScope {
        if let existing = objc_getAssociatedObject(self, &flowScopeKey) as? FlowScope {
            return existing
        }
        let scope = FlowScope()
        objc_setAssociatedObject(self, &flowScopeKey, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scope
    }

    /// Collects a `StateFlow`, calling `action` on the main actor for each
    /// emitted value. Collection is tied to this view controller's `flowScope`
    /// and is cancelled when the view controller is deallocated.
    public func collect<T: Sendable & Equatable>(
        _ stateFlow: any StateFlow<T>,
        action: @escaping @MainActor (T) -> Void
    ) {
        stateFlow.asFlow()
            .onEach { value in await MainActor.run { action(value) } }
            .launch(in: flowScope)
    }

    /// Collects a cold `Flow`, calling `action` on the main actor for each
    /// emitted value. Collection is tied to this view controller's `flowScope`
    /// and is cancelled when the view controller is deallocated.
    public func collect<T: Sendable>(
        _ flow: Flow<T>,
        action: @escaping @MainActor (T) -> Void
    ) {
        flow.onEach { value in await MainActor.run { action(value) } }
            .launch(in: flowScope)
    }
}
#endif
