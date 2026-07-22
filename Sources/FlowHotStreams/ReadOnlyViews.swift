public import FlowCore

extension MutableStateFlow {
    /// Returns a read-only view of this state flow.
    ///
    /// The view tracks this flow live: reads and subscriptions observe every
    /// later mutation of the source, but the view's surface exposes no
    /// mutation members and cannot be cast back to `MutableStateFlow`. Use it
    /// to hand state to consumers while only the owner mutates, mirroring
    /// Kotlin's `MutableStateFlow.asStateFlow()`.
    ///
    /// - Returns: A `StateFlow` view over this flow.
    public nonisolated func asStateFlow() -> any StateFlow<Element> {
        ReadOnlyStateFlow(base: self)
    }
}

extension MutableSharedFlow {
    /// Returns a read-only view of this shared flow.
    ///
    /// The view tracks this flow live: subscriptions observe every later
    /// emission (including replay), but the view's surface exposes no
    /// mutation members and cannot be cast back to `MutableSharedFlow`. Use
    /// it to hand a broadcast stream to consumers while only the owner emits,
    /// mirroring Kotlin's `MutableSharedFlow.asSharedFlow()`.
    ///
    /// - Returns: A `SharedFlow` view over this flow.
    public nonisolated func asSharedFlow() -> any SharedFlow<Element> {
        ReadOnlySharedFlow(base: self)
    }
}

/// A `StateFlow` wrapper that forwards reads and subscriptions to a
/// `MutableStateFlow` without exposing its mutation members.
private struct ReadOnlyStateFlow<Element: Sendable & Equatable>: StateFlow {
    let base: MutableStateFlow<Element>

    var value: Element {
        get async { await base.value }
    }

    func asFlow() -> Flow<Element> {
        base.asFlow()
    }
}

/// A `SharedFlow` wrapper that forwards subscriptions to a
/// `MutableSharedFlow` without exposing its mutation members.
private struct ReadOnlySharedFlow<Element: Sendable>: SharedFlow {
    let base: MutableSharedFlow<Element>

    var subscriptionCount: Int {
        get async { await base.subscriptionCount }
    }

    func asFlow() -> Flow<Element> {
        base.asFlow()
    }
}
