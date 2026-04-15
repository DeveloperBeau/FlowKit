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
