public import FlowCore

/// A shared flow that can suspend until its subscriber count moves. Internal:
/// the public `SharedFlow` protocol gains no requirement, and tests reach the
/// waiters of a type-erased flow through this.
internal protocol SubscriberCountWaiting: Sendable {
    func waitForSubscribers(_ count: Int) async throws
    func waitForSubscribers(atMost count: Int) async throws
}

public protocol SharedFlow<Element>: Sendable {
    associatedtype Element: Sendable
    var subscriptionCount: Int { get async }
    func asFlow() -> Flow<Element>
}
