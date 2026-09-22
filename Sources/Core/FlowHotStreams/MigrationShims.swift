// Compile-time migration rails for hot-stream types: unavailable aliases so
// RxSwift subject and Combine subject names produce fix-its or messages
// pointing at the FlowKit equivalent. Nothing here can execute.

// MARK: - RxSwift subjects

@available(*, unavailable, renamed: "MutableSharedFlow", message: "a PublishSubject is a MutableSharedFlow with replay: 0")
public typealias PublishSubject<Element: Sendable> = MutableSharedFlow<Element>

@available(*, unavailable, renamed: "MutableStateFlow", message: "a BehaviorSubject is a MutableStateFlow seeded with its initial value")
public typealias BehaviorSubject<Element: Sendable & Equatable> = MutableStateFlow<Element>

@available(*, unavailable, renamed: "MutableStateFlow", message: "a BehaviorRelay is a MutableStateFlow; it cannot fail by construction")
public typealias BehaviorRelay<Element: Sendable & Equatable> = MutableStateFlow<Element>

@available(*, unavailable, renamed: "MutableSharedFlow", message: "a ReplaySubject is a MutableSharedFlow with replay: n")
public typealias ReplaySubject<Element: Sendable> = MutableSharedFlow<Element>

// MARK: - Combine subjects

@available(*, unavailable, message: "use MutableStateFlow(initialValue); failure typing is structural in FlowKit")
public typealias CurrentValueSubject<Output: Sendable & Equatable, Failure: Error> = MutableStateFlow<Output>

@available(*, unavailable, message: "use MutableSharedFlow(replay: 0); failure typing is structural in FlowKit")
public typealias PassthroughSubject<Output: Sendable, Failure: Error> = MutableSharedFlow<Output>
