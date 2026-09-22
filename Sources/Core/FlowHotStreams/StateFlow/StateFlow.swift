public import FlowCore

/// A hot flow that always has a current value, readable synchronously,
/// mirroring Kotlin's `StateFlow`. Collectors receive the current value on
/// subscription and every distinct update after it.
public protocol StateFlow<Element>: Sendable {
    associatedtype Element: Sendable & Equatable

    /// The current value. Synchronous, like Kotlin's `StateFlow.value`.
    var value: Element { get }

    func asFlow() -> Flow<Element>
}
