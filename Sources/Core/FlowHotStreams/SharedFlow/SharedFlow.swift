public import FlowCore

public protocol SharedFlow<Element>: Sendable {
    associatedtype Element: Sendable
    var subscriptionCount: Int { get async }
    func asFlow() -> Flow<Element>
}
