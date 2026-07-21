import Foundation
public import FlowCore

public actor MutableStateFlow<Element: Sendable & Equatable>: StateFlow {
    private var currentValue: Element
    private let subscription: MulticastSubscription<Element>

    public init(_ initialValue: Element) {
        self.currentValue = initialValue
        self.subscription = MulticastSubscription<Element>()
    }

    public var value: Element { currentValue }

    public func send(_ newValue: Element) async {
        guard newValue != currentValue else { return }
        currentValue = newValue
        await subscription.deliver(newValue)
    }

    public func update(_ transform: @Sendable (Element) -> Element) async {
        let newValue = transform(currentValue)
        await send(newValue)
    }

    public nonisolated func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            let (id, stream) = await self.subscription.makeSubscription()
            let initialValue = await self.currentValue
            await self.subscription.deliver(initialValue, to: id)

            for await value in stream {
                await collector.emit(value)
                if Task.isCancelled { break }
            }

            await self.subscription.unsubscribe(id: id)
        }
    }
}

extension MutableStateFlow {
    /// Atomically applies `transform` and returns the value that was current
    /// before the update.
    @discardableResult
    public func getAndUpdate(_ transform: @Sendable (Element) -> Element) async -> Element {
        let previous = value
        await send(transform(previous))
        return previous
    }

    /// Atomically applies `transform` and returns the resulting value.
    @discardableResult
    public func updateAndGet(_ transform: @Sendable (Element) -> Element) async -> Element {
        let next = transform(value)
        await send(next)
        return next
    }

    /// Sets `newValue` only if the current value equals `expected`. Returns
    /// whether the swap happened.
    @discardableResult
    public func compareAndSet(expected: Element, newValue: Element) async -> Bool {
        guard value == expected else { return false }
        await send(newValue)
        return true
    }
}
