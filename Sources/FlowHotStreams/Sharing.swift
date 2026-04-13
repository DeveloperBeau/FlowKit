import Foundation
public import FlowCore
public import FlowSharedModels

extension Flow where Element: Equatable {
    /// Converts this cold flow into a hot `StateFlow` with the given initial
    /// value and sharing strategy.
    public func asStateFlow(
        initialValue: Element,
        strategy: SharingStrategy = .whileSubscribed(stopTimeout: .seconds(5))
    ) -> any StateFlow<Element> {
        let state = MutableStateFlow(initialValue)

        let coordinator = SharingCoordinator(
            strategy: strategy,
            clock: ContinuousClock(),
            start: {
                Task {
                    await self.collect { value in
                        await state.send(value)
                    }
                }
            },
            stop: {}
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
    public func asSharedFlow(
        replay: Int = 0,
        strategy: SharingStrategy = .whileSubscribed(stopTimeout: .seconds(5))
    ) -> any SharedFlow<Element> {
        let shared = MutableSharedFlow<Element>(replay: replay)

        let coordinator = SharingCoordinator(
            strategy: strategy,
            clock: ContinuousClock(),
            start: {
                Task {
                    await self.collect { value in
                        await shared.emit(value)
                    }
                }
            },
            stop: {}
        )

        return CoordinatedSharedFlow(
            inner: shared,
            coordinator: coordinator
        )
    }
}

// MARK: - Internal coordinated wrappers

private actor CoordinatedStateFlow<Element: Sendable & Equatable>: StateFlow {
    private let inner: MutableStateFlow<Element>
    private let coordinator: SharingCoordinator
    private var activated: Bool = false

    init(inner: MutableStateFlow<Element>, coordinator: SharingCoordinator) {
        self.inner = inner
        self.coordinator = coordinator
        // Activate immediately so eager strategies start upstream at creation time.
        Task { await coordinator.activate() }
    }

    var value: Element {
        get async { await inner.value }
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
