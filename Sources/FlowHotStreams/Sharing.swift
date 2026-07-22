import Foundation
public import FlowCore
public import FlowSharedModels

extension Flow where Element: Equatable {
    /// Converts this cold flow into a hot `StateFlow` with the given initial
    /// value and sharing strategy.
    ///
    /// The default strategy is `.whileSubscribed()` with a zero stop timeout,
    /// matching Kotlin's `WhileSubscribed()`: the upstream stops as soon as
    /// the last subscriber leaves. Pass an explicit
    /// `stopTimeout` (e.g. `.seconds(5)`) to survive brief resubscribe gaps.
    ///
    /// - Parameter clock: The clock the sharing strategy times its stop delay
    ///   against. Injectable so a test can drive `whileSubscribed`'s timeout
    ///   with virtual time.
    public func asStateFlow(
        initialValue: Element,
        strategy: SharingStrategy = .whileSubscribed(),
        clock: any Clock<Duration> = ContinuousClock()
    ) -> any StateFlow<Element> {
        let state = MutableStateFlow(initialValue)
        let source = self
        // Holds the running upstream collection so `stop` can cancel it.
        // Without this the collection Task is orphaned and `whileSubscribed`
        // never actually stops the source.
        let upstream = Mutex<Task<Void, Never>?>(nil)

        let coordinator = SharingCoordinator(
            strategy: strategy,
            clock: clock,
            start: {
                let task = Task { await source.collect { value in state.send(value) } }
                upstream.withLock { previous in
                    previous?.cancel()
                    previous = task
                }
            },
            stop: {
                upstream.withLock { task in
                    task?.cancel()
                    task = nil
                }
            }
        )

        return CoordinatedStateFlow(
            inner: state,
            coordinator: coordinator
        )
    }
}

extension Flow {
    /// Converts this cold flow into a hot `SharedFlow` with the given replay
    /// buffer size and sharing strategy.
    ///
    /// The default strategy is `.whileSubscribed()` with a zero stop timeout,
    /// matching Kotlin's `WhileSubscribed()`: the upstream stops as soon as
    /// the last subscriber leaves. Pass an explicit
    /// `stopTimeout` (e.g. `.seconds(5)`) to survive brief resubscribe gaps.
    ///
    /// - Parameter clock: The clock the sharing strategy times its stop delay
    ///   against. Injectable so a test can drive `whileSubscribed`'s timeout
    ///   with virtual time.
    public func asSharedFlow(
        replay: Int = 0,
        strategy: SharingStrategy = .whileSubscribed(),
        clock: any Clock<Duration> = ContinuousClock()
    ) -> any SharedFlow<Element> {
        let shared = MutableSharedFlow<Element>(replay: replay)
        let source = self
        let upstream = Mutex<Task<Void, Never>?>(nil)

        let coordinator = SharingCoordinator(
            strategy: strategy,
            clock: clock,
            start: {
                let task = Task { await source.collect { value in await shared.emit(value) } }
                upstream.withLock { previous in
                    previous?.cancel()
                    previous = task
                }
            },
            stop: {
                upstream.withLock { task in
                    task?.cancel()
                    task = nil
                }
            }
        )

        return CoordinatedSharedFlow(
            inner: shared,
            coordinator: coordinator
        )
    }
}

// MARK: - Internal coordinated wrappers

private final class CoordinatedStateFlow<Element: Sendable & Equatable>: StateFlow, Sendable {
    private let inner: MutableStateFlow<Element>
    private let coordinator: SharingCoordinator
    private let activated = Mutex(false)

    init(inner: MutableStateFlow<Element>, coordinator: SharingCoordinator) {
        self.inner = inner
        self.coordinator = coordinator
        // Activate immediately so eager strategies start upstream at creation time.
        Task { await coordinator.activate() }
    }

    var value: Element { inner.value }

    func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            await self.ensureActivated()
            await self.coordinator.subscriberDidAppear()
            defer {
                Task { [weak self] in
                    await self?.coordinator.subscriberDidDisappear()
                }
            }
            await self.inner.asFlow().collect { value in
                await collector.emit(value)
            }
        }
    }

    private func ensureActivated() async {
        let firstActivation = activated.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        if firstActivation { await coordinator.activate() }
    }
}

private actor CoordinatedSharedFlow<Element: Sendable>: SharedFlow {
    private let inner: MutableSharedFlow<Element>
    private let coordinator: SharingCoordinator
    private var activated: Bool = false

    init(inner: MutableSharedFlow<Element>, coordinator: SharingCoordinator) {
        self.inner = inner
        self.coordinator = coordinator
        // Activate immediately so eager strategies start upstream at creation time.
        Task { await coordinator.activate() }
    }

    var subscriptionCount: Int {
        get async { await inner.subscriptionCount }
    }

    nonisolated func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            await self.ensureActivated()
            await self.coordinator.subscriberDidAppear()
            defer {
                Task { [weak self] in
                    await self?.coordinator.subscriberDidDisappear()
                }
            }
            await self.inner.asFlow().collect { value in
                await collector.emit(value)
            }
        }
    }

    private func ensureActivated() async {
        guard !activated else { return }
        activated = true
        await coordinator.activate()
    }
}
