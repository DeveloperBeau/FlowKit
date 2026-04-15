internal import Foundation
public import FlowCore
public import FlowSharedModels

public actor MutableSharedFlow<Element: Sendable>: SharedFlow {
    private let replayCount: Int
    private let bufferCapacity: Int
    private let overflow: BufferOverflow

    private var replayBuffer: RingBufferAdapter<Element>
    private let subscription: MulticastSubscription<Element>

    public init(
        replay: Int = 0,
        extraBufferCapacity: Int = 0,
        onBufferOverflow: BufferOverflow = .suspend
    ) {
        precondition(replay >= 0, "replay must be non-negative")
        precondition(extraBufferCapacity >= 0, "extraBufferCapacity must be non-negative")
        self.replayCount = replay
        self.bufferCapacity = replay + extraBufferCapacity
        self.overflow = onBufferOverflow
        self.replayBuffer = RingBufferAdapter(capacity: replay)
        self.subscription = MulticastSubscription<Element>()
    }

    public var subscriptionCount: Int {
        get async { await subscription.subscriberCount }
    }

    public func emit(_ value: Element) async {
        await subscription.deliver(value)
        if replayCount > 0 {
            replayBuffer.append(value)
        }
    }

    public func resetReplayCache() {
        replayBuffer = RingBufferAdapter(capacity: replayCount)
    }

    public nonisolated func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            let (id, stream) = await self.subscription.makeSubscription()

            let replay = await self.currentReplayElements()
            for value in replay {
                await self.subscription.deliver(value, to: id)
            }

            for await value in stream {
                await collector.emit(value)
                if Task.isCancelled { break }
            }

            await self.subscription.unsubscribe(id: id)
        }
    }

    private func currentReplayElements() -> [Element] {
        replayBuffer.elements
    }
}

internal struct RingBufferAdapter<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var head: Int = 0
    private var size: Int = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity >= 0)
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        guard capacity > 0 else { return }
        let writeIndex = (head + size) % capacity
        storage[writeIndex] = element
        if size == capacity {
            head = (head + 1) % capacity
        } else {
            size += 1
        }
    }

    var elements: [Element] {
        var result: [Element] = []
        result.reserveCapacity(size)
        for i in 0..<size {
            if let value = storage[(head + i) % capacity] {
                result.append(value)
            }
        }
        return result
    }
}
