internal import Foundation
public import FlowCore
public import FlowSharedModels

public actor MutableSharedFlow<Element: Sendable>: SharedFlow, SubscriberCountWaiting {
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
        self.subscription = MulticastSubscription<Element>(
            bufferingPolicy: Self.subscriberBufferingPolicy(
                capacity: replay + extraBufferCapacity,
                overflow: onBufferOverflow
            )
        )
    }

    /// Maps the buffer capacity and overflow policy to a per-subscriber
    /// `AsyncStream` buffering policy.
    ///
    /// A capacity of zero, or the `.suspend` policy, falls back to unbounded:
    /// zero has no room to bound, and `.suspend` needs the emitter to
    /// backpressure, which an `AsyncStream` continuation cannot do. The drop
    /// policies map to a bounded buffer, so a slow subscriber conflates
    /// (`.dropOldest`) or sheds new values (`.dropLatest`) instead of growing
    /// without bound.
    private static func subscriberBufferingPolicy(
        capacity: Int,
        overflow: BufferOverflow
    ) -> AsyncStream<Element>.Continuation.BufferingPolicy {
        guard capacity > 0 else { return .unbounded }
        switch overflow {
        case .dropOldest:
            return .bufferingNewest(capacity)
        case .dropLatest:
            return .bufferingOldest(capacity)
        case .suspend:
            return .unbounded
        }
    }

    public var subscriptionCount: Int {
        get async { await subscription.subscriberCount }
    }

    /// Suspends until at least `count` collectors are attached, then returns.
    /// Returns at once if that many already are.
    ///
    /// The push counterpart of polling ``subscriptionCount``: the flow's own
    /// subscribe path resumes the waiter, so a test (or a producer that must
    /// not emit into the void) waits for a collector to have attached without
    /// a poll loop or a real-time bound.
    ///
    /// ```swift
    /// let collector = Task { await flow.asFlow().collect { _ in } }
    /// try await flow.waitForSubscribers(1)
    /// ```
    ///
    /// - Parameter count: The number of attached collectors to wait for.
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    public func waitForSubscribers(_ count: Int) async throws {
        try await subscription.waitForSubscriberCount { $0 >= count }
    }

    /// Suspends until at most `count` collectors remain attached, then
    /// returns. Returns at once if no more than that many already are.
    ///
    /// The push counterpart of polling ``subscriptionCount`` for it to fall:
    /// the flow's own unsubscribe path resumes the waiter, so a test can wait
    /// for a cancelled collector to have detached before asserting on it.
    /// `waitForSubscribers(atMost: 0)` waits for the last collector to leave.
    ///
    /// - Parameter count: The largest number of attached collectors to accept.
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    public func waitForSubscribers(atMost count: Int) async throws {
        try await subscription.waitForSubscriberCount { $0 <= count }
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

extension MutableSharedFlow {
    /// The values a new subscriber would receive on subscription, oldest
    /// first. Empty when `replay` is zero.
    public var replayCache: [Element] { replayBuffer.elements }
}
