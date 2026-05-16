#if canImport(AppKit) && !targetEnvironment(macCatalyst)
public import AppKit
import ObjectiveC
public import FlowCore
public import FlowHotStreams
import FlowOperators

// A bare, stateless final class is implicitly Sendable. Single global
// instances provide stable, app-lifetime pointers for use as
// associated-object keys, with no `nonisolated(unsafe)` required.
private final class FlowScopeKey: Sendable {}
private let nsViewControllerFlowScopeKey = FlowScopeKey()
private let nsWindowControllerFlowScopeKey = FlowScopeKey()

extension NSViewController {
    /// A `FlowScope` tied to this view controller's lifetime. Created
    /// lazily on first access. Cancelled automatically when the view
    /// controller is deallocated (because the associated object is released).
    public var flowScope: FlowScope {
        let key = Unmanaged.passUnretained(nsViewControllerFlowScopeKey).toOpaque()
        if let existing = objc_getAssociatedObject(self, key) as? FlowScope {
            return existing
        }
        let scope = FlowScope()
        objc_setAssociatedObject(self, key, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        let key = Unmanaged.passUnretained(nsWindowControllerFlowScopeKey).toOpaque()
        if let existing = objc_getAssociatedObject(self, key) as? FlowScope {
            return existing
        }
        let scope = FlowScope()
        objc_setAssociatedObject(self, key, scope, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return scope
    }
}
#endif
