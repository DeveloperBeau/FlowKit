public import FlowCore

public protocol StateFlow<Element>: Sendable {
    associatedtype Element: Sendable & Equatable
    var value: Element { get async }
    func asFlow() -> Flow<Element>
}
