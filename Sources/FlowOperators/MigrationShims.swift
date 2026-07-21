public import FlowCore

// Compile-time migration rails: every declaration here is unavailable and
// exists only so a dev arriving from RxSwift or Combine who types the old
// name gets a fix-it or message pointing at the FlowKit spelling. Nothing in
// this file can execute.

// MARK: - RxSwift

@available(*, unavailable, renamed: "Flow", message: "RxSwift's Observable maps to Flow (or ThrowingFlow when the source can fail)")
public typealias Observable<Element: Sendable> = Flow<Element>

extension Flow {
    @available(*, unavailable, renamed: "collect(_:)", message: "flows are collected, not subscribed: await flow.collect { value in ... }")
    public func subscribe(onNext: @escaping @Sendable (Element) -> Void) { fatalError() }

    @available(*, unavailable, message: "FlowKit has no disposables; use launch(in:) with a FlowScope and cancel the scope")
    public func disposed(by bag: Any) { fatalError() }

    @available(*, unavailable, renamed: "removeDuplicates()")
    public func distinctUntilChanged() -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "use onStart { await $0.emit(value) } to prepend a value")
    public func startWith(_ value: Element) -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "there is no scheduler hopping; isolate the collecting side with an actor or @MainActor")
    public func observe(on scheduler: Any) -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "there is no scheduler hopping; the flow body runs where it is collected")
    public func subscribeOn(_ scheduler: Any) -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "use combineLatest and read the other flow's latest value from the tuple")
    public func withLatestFrom<Other: Sendable>(_ other: Flow<Other>) -> Flow<Other> { fatalError() }

    @available(*, unavailable, renamed: "asSharedFlow(replay:strategy:clock:)")
    public func share(replay: Int) -> Flow<Element> { fatalError() }
}

extension ThrowingFlow {
    @available(*, unavailable, renamed: "catch(_:)")
    public func catchError(_ handler: @escaping @Sendable (any Error) -> ThrowingFlow<Element>) -> ThrowingFlow<Element> { fatalError() }

    @available(*, unavailable, message: "use catch { _, collector in await collector.emit(fallback) }")
    public func catchErrorJustReturn(_ fallback: Element) -> ThrowingFlow<Element> { fatalError() }
}

// MARK: - Combine

extension Flow {
    @available(*, unavailable, renamed: "collect(_:)", message: "flows are collected, not sunk: await flow.collect { value in ... }")
    public func sink(receiveValue: @escaping @Sendable (Element) -> Void) { fatalError() }

    @available(*, unavailable, message: "FlowKit has no cancellable sets; use launch(in:) with a FlowScope and cancel the scope")
    public func store(in set: Any) { fatalError() }

    @available(*, unavailable, message: "flows need no type erasure; Flow<Element> is already the universal currency")
    public func eraseToAnyPublisher() -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "there is no scheduler hopping; isolate the collecting side with an actor or @MainActor")
    public func receive(on scheduler: Any) -> Flow<Element> { fatalError() }

    @available(*, unavailable, renamed: "mapThrowing(_:)")
    public func tryMap<U: Sendable>(_ transform: @escaping @Sendable (Element) throws -> U) -> ThrowingFlow<U> { fatalError() }

    @available(*, unavailable, message: "failure typing is structural: Flow cannot fail, ThrowingFlow can; convert with mapThrowing or catch")
    public func setFailureType(to failureType: Any) -> ThrowingFlow<Element> { fatalError() }

    @available(*, unavailable, message: "use onEmpty { await $0.emit(fallback) }")
    public func replaceEmpty(with fallback: Element) -> Flow<Element> { fatalError() }

    @available(*, unavailable, message: "use onStart/onEach/onCompletion for side effects")
    public func handleEvents() -> Flow<Element> { fatalError() }
}
