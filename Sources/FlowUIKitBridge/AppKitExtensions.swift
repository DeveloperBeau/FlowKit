#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
import ObjectiveC
public import FlowCore
public import FlowHotStreams
import FlowOperators

// nonisolated(unsafe) var gives a stable address for use as associated-object
// keys. The value is never mutated; only its address is used.
private nonisolated(unsafe) var nsViewControllerFlowScopeKey: UInt8 = 0
private nonisolated(unsafe) var nsWindowControllerFlowScopeKey: UInt8 = 0

extension NSViewController {
    /// A `FlowScope` tied to this view controller's lifetime. Created
    /// lazily on first access. Cancelled automatically when the view
    /// controller is deallocated (because the associated object is released).
    public var flowScope: FlowScope {
        if let existing = objc_getAssociatedObject(self, &nsViewControllerFlowScopeKey) as? FlowScope {
            return existing
        }
        let scope = FlowScope()
        objc_setAssociatedObject(self, &nsViewControllerFlowScopeKey, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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

extension NSWindowController {
    /// A `FlowScope` tied to this window controller's lifetime. Created
    /// lazily on first access. Cancelled automatically when the window
    /// controller is deallocated (because the associated object is released).
    public var flowScope: FlowScope {
        if let existing = objc_getAssociatedObject(self, &nsWindowControllerFlowScopeKey) as? FlowScope {
            return existing
        }
        let scope = FlowScope()
        objc_setAssociatedObject(self, &nsWindowControllerFlowScopeKey, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scope
    }
}
#endif
