internal import Foundation
public import FlowCore
public import FlowSharedModels

public actor MutableSharedFlow<Element: Sendable>: SharedFlow, SubscriberCountWaiting {
    private let replayCount: Int
    private let bufferCapacity: Int
    private let overflow: BufferOverflow

    /// The replay values. They sit behind a lock, not behind the actor, so
    /// that `tryEmit(_:)` can store a value from synchronous code.
    private let replayBuffer: Mutex<RingBufferAdapter<Element>>
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
        self.replayBuffer = Mutex(RingBufferAdapter(capacity: replay))
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
        tryEmit(value)
    }

    /// Publishes `value` to the current subscribers and the replay cache without suspending.
    ///
    /// Use it where the caller cannot `await`: a delegate method, a
    /// notification block, a C callback. It is safe from any thread. Calls
    /// made one after another from one thread reach each subscriber in that
    /// order. Calls that race each other reach every subscriber, and the
    /// replay cache, in one common order.
    ///
    /// ```swift
    /// func didTap(_ tap: Tap) {
    ///     taps.tryEmit(tap)
    /// }
    /// ```
    ///
    /// It never waits for a subscriber. A slow subscriber is handled by the
    /// `onBufferOverflow` policy of the flow, the same as for `emit(_:)`.
    ///
    /// - Parameter value: The value to publish.
    /// - Returns: `true` when the flow accepted the value, and `false` after
    ///   ``close()``. Every policy this flow has today accepts: `.suspend`
    ///   buffers without a bound for each subscriber, and the drop policies
    ///   shed a value for a slow subscriber and do not refuse it.
    @discardableResult
    public nonisolated func tryEmit(_ value: Element) -> Bool {
        // The replay lock is held across the fan-out, so the replay cache
        // keeps the same order the subscribers see when callers race. A
        // closed flow refuses the value, and its replay cache stays as it was.
        replayBuffer.withLock { replayBuffer in
            // A registered subscriber gets the replay before this value.
            if replayCount > 0 {
                subscription.replayToRegistrations { replayBuffer.elements }
            }
            guard subscription.deliverWithoutSuspending(value) else { return false }
            replayBuffer.append(value)
            return true
        }
    }

    /// Ends the flow: every attached collector receives the values already
    /// emitted to it, then its `collect` returns.
    ///
    /// Close is final and safe to call more than once. After it, `emit` and
    /// `tryEmit` publish nothing and leave ``replayCache`` as it was,
    /// `tryEmit` returns `false`, and a new collector
    /// returns at once without the replay. ``subscriptionCount`` is zero, so
    /// `waitForSubscribers(atMost: 0)` returns, and `waitForSubscribers(_:)`
    /// for one or more collectors stays suspended until its task is cancelled.
    ///
    /// ```swift
    /// let events = MutableSharedFlow<Event>()
    /// let observer = Task {
    ///     await events.asFlow().collect { handle($0) }
    ///     cleanUp() // runs after close
    /// }
    /// await events.close()
    /// ```
    public func close() async {
        await subscription.finishAll()
    }

    public func resetReplayCache() {
        replayBuffer.withLock { $0 = RingBufferAdapter(capacity: replayCount) }
    }

    public nonisolated func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            // The subscriber waits for its replay from the moment it is
            // registered, so a value published before the replay is read
            // arrives after the replay, and one time only.
            let (id, stream) = self.subscription.register(awaitingReplay: self.replayCount > 0)
            self.replayToRegistrations()

            for await value in stream {
                await collector.emit(value)
                if Task.isCancelled { break }
            }

            self.subscription.unregister(id: id)
        }
    }
}

extension MutableSharedFlow {
    /// Registers a subscriber before it returns, and gives the flow that
    /// reads it.
    ///
    /// ``asFlow()`` registers its subscriber when a task starts to collect it,
    /// so a value emitted before that task first runs is lost with
    /// `replay: 0`. This method registers at the call. Every value emitted
    /// after it returns is delivered, even when the collection starts later.
    ///
    /// ```swift
    /// let incoming = events.subscribed()      // registered here
    /// let consumer = Task {
    ///     await incoming.collect { handle($0) }
    /// }
    /// connection.start()                      // nothing is missed
    /// ```
    ///
    /// Values wait in the subscriber's buffer until the flow is collected. The
    /// buffer follows the overflow policy and capacity of this shared flow,
    /// the same as an ``asFlow()`` subscriber. A flow with a replay delivers
    /// the replay cache first.
    ///
    /// The subscriber counts in ``subscriptionCount`` from the call. It is
    /// removed when the collecting task is cancelled, and when the returned
    /// flow is released without a collection.
    ///
    /// The returned flow can be collected once. A second collection completes
    /// at once and emits nothing. If this shared flow is released first, the
    /// collection emits the buffered values and then completes.
    ///
    /// - Returns: A flow of the values emitted after this call.
    public nonisolated func subscribed() -> Flow<Element> {
        let registration = RegisteredSubscription(in: subscription, awaitingReplay: replayCount > 0)
        return Flow<Element> { [weak self] collector in
            guard registration.claimCollection() else { return }
            if let self {
                self.replayToRegistrations()
            } else {
                registration.cancel()
            }

            for await value in registration.stream {
                await collector.emit(value)
                if Task.isCancelled { break }
            }

            registration.cancel()
        }
    }

    /// Yields the replay cache to each registered subscriber that has not had
    /// it. This runs before a delivery, so the replay comes before the value.
    /// It holds the replay lock, the same as `tryEmit(_:)`, so the replay
    /// and a racing value reach the subscriber in the order of the cache.
    private nonisolated func replayToRegistrations() {
        guard replayCount > 0 else { return }
        replayBuffer.withLock { replayBuffer in
            subscription.replayToRegistrations { replayBuffer.elements }
        }
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
    public var replayCache: [Element] { replayBuffer.withLock { $0.elements } }
}
