public import FlowCore
internal import FlowSharedModels

/// A hot, observable value container with synchronous access, mirroring
/// Kotlin's `MutableStateFlow`.
///
/// `value` reads and writes synchronously from any thread — control surfaces
/// (toggles, overrides) can mutate state without adopting `async` signatures.
/// Collectors receive the current value on subscription and every distinct
/// update after it; setting an equal value is a no-op.
///
/// ## Ordering
///
/// Updates are totally ordered by a lock: every collector observes updates in
/// the global order they were applied, and a synchronous `value` read never
/// observes a torn or stale-out-of-order value. Delivery to collectors is
/// asynchronous — a set returns immediately; collectors catch up in order.
public final class MutableStateFlow<Element: Sendable & Equatable>: StateFlow, Sendable {
    private struct Storage {
        var value: Element
        /// Global update ordinal. Bumped under the lock on every distinct
        /// set, so a stamped delivery can be ordered against a snapshot.
        var seq: UInt64 = 0
        /// Set by `close()` and never cleared. A closed flow keeps its value.
        var isClosed = false
    }

    /// A value paired with the update ordinal it was produced by, so a
    /// subscriber can discard deliveries at or before the snapshot it
    /// started from.
    private struct Stamped: Sendable {
        let seq: UInt64
        let value: Element
    }

    private let storage: Mutex<Storage>
    private let subscription: MulticastSubscription<Stamped>
    /// Single ordered pipeline from setters to the multicast delivery task.
    /// Values are enqueued while the lock is held, so pipeline order equals
    /// update order.
    private let pipeline: AsyncStream<Stamped>.Continuation

    public init(_ initialValue: Element) {
        let subscription = MulticastSubscription<Stamped>()
        let (stream, continuation) = AsyncStream<Stamped>.makeStream()
        self.storage = Mutex(Storage(value: initialValue))
        self.subscription = subscription
        self.pipeline = continuation
        // A single drainer task preserves the global update order for every
        // subscriber. It holds the subscription, not self, so the state flow
        // can deinit; finishing the pipeline ends the task.
        Task {
            for await stamped in stream {
                await subscription.deliver(stamped)
            }
            await subscription.finishAll()
        }
    }

    deinit {
        pipeline.finish()
    }

    /// The current value. Reads and writes are synchronous and safe from any
    /// thread; writing an equal value is a no-op.
    public var value: Element {
        get { storage.withLock { $0.value } }
        set { send(newValue) }
    }

    /// The number of collectors currently attached via `asFlow()`, matching
    /// `MutableSharedFlow.subscriptionCount`. Use it to collect an upstream
    /// flow only while the state is observed (Kotlin's `WhileSubscribed`
    /// ViewModel convention).
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

    /// Sets `newValue` as the current value. Equivalent to writing `value`;
    /// a no-op when `newValue` equals the current value.
    public func send(_ newValue: Element) {
        storage.withLock { state in
            guard !state.isClosed, newValue != state.value else { return }
            state.value = newValue
            state.seq += 1
            pipeline.yield(Stamped(seq: state.seq, value: newValue))
        }
    }

    /// Ends the flow: every attached collector receives the updates applied
    /// before the close, then its `collect` returns.
    ///
    /// Close is final and safe to call more than once, from any thread. After
    /// it, ``value`` still reads the last value and every write is ignored:
    /// setting ``value``, ``send(_:)`` and ``compareAndSet(expected:newValue:)``
    /// change nothing, and the update family returns the last value without
    /// running its transform. A collector that attaches after the close
    /// receives the last value, then returns.
    ///
    /// ```swift
    /// let states = MutableStateFlow(State.idle)
    /// let observer = Task {
    ///     await states.asFlow().collect { render($0) }
    ///     cleanUp() // runs after close
    /// }
    /// states.close()
    /// ```
    public func close() {
        storage.withLock { state in
            guard !state.isClosed else { return }
            state.isClosed = true
            // Under the lock, so every applied update is already in the
            // pipeline. The drainer delivers them, then finishes the subscribers.
            pipeline.finish()
        }
    }

    /// Atomically applies `transform` to the current value and stores the
    /// result. `transform` may run multiple times when writers race (Kotlin's
    /// CAS-loop semantics); it runs outside the lock, so it may freely read
    /// the flow.
    public func update(_ transform: (Element) -> Element) {
        updateAndGet(transform)
    }

    public nonisolated func asFlow() -> Flow<Element> {
        Flow<Element> { [weak self] collector in
            guard let self else { return }
            let (id, stream) = await self.subscription.makeSubscription()
            // Snapshot after registering: every update the snapshot misses is
            // enqueued after registration and therefore reaches the stream;
            // anything at or before the snapshot is filtered by its ordinal.
            let snapshot = self.storage.withLock { (seq: $0.seq, value: $0.value) }
            var lastSeq = snapshot.seq
            await collector.emit(snapshot.value)

            for await stamped in stream {
                guard stamped.seq > lastSeq else { continue }
                lastSeq = stamped.seq
                await collector.emit(stamped.value)
                if Task.isCancelled { break }
            }

            await self.subscription.unsubscribe(id: id)
        }
    }
}

extension MutableStateFlow {
    /// Registers a subscriber before it returns, and gives the flow that
    /// reads it.
    ///
    /// ``asFlow()`` registers its subscriber when a task starts to collect it,
    /// so it starts from the value at that later time. This method registers
    /// at the call. The returned flow emits the value that was current at the
    /// call, then every later distinct update, even when the collection starts
    /// later.
    ///
    /// ```swift
    /// let changes = state.subscribed()        // registered here
    /// let consumer = Task {
    ///     await changes.collect { render($0) }
    /// }
    /// ```
    ///
    /// The subscriber counts in ``subscriptionCount`` from the call. It is
    /// removed when the collecting task is cancelled, and when the returned
    /// flow is released without a collection.
    ///
    /// The returned flow can be collected once. A second collection completes
    /// at once and emits nothing. If this state flow is released first, the
    /// collection emits the buffered values and then completes.
    ///
    /// - Returns: A flow of the value at this call and the updates after it.
    public func subscribed() -> Flow<Element> {
        let registration = RegisteredSubscription(in: subscription)
        // Snapshot after registering, for the same reason as `asFlow()`: an
        // update the snapshot misses reaches the stream, and its ordinal
        // filters anything at or before the snapshot.
        let snapshot = storage.withLock { Stamped(seq: $0.seq, value: $0.value) }
        return Flow<Element> { collector in
            guard registration.claimCollection() else { return }
            var lastSeq = snapshot.seq
            await collector.emit(snapshot.value)

            for await stamped in registration.stream {
                guard stamped.seq > lastSeq else { continue }
                lastSeq = stamped.seq
                await collector.emit(stamped.value)
                if Task.isCancelled { break }
            }

            registration.cancel()
        }
    }
}

extension MutableStateFlow {
    /// Atomically applies `transform` and returns the value that was current
    /// before the update. May re-run `transform` when writers race.
    @discardableResult
    public func getAndUpdate(_ transform: (Element) -> Element) -> Element {
        mutate(transform).previous
    }

    /// Atomically applies `transform` and returns the resulting value.
    /// May re-run `transform` when writers race.
    @discardableResult
    public func updateAndGet(_ transform: (Element) -> Element) -> Element {
        mutate(transform).next
    }

    /// Sets `newValue` only if the current value equals `expected`. Returns
    /// whether the swap happened. A closed flow accepts no new value, so the
    /// result is then `false` unless `newValue` is already the current value.
    @discardableResult
    public func compareAndSet(expected: Element, newValue: Element) -> Bool {
        storage.withLock { state in
            guard state.value == expected else { return false }
            guard newValue != state.value else { return true }
            guard !state.isClosed else { return false }
            state.value = newValue
            state.seq += 1
            pipeline.yield(Stamped(seq: state.seq, value: newValue))
            return true
        }
    }

    /// CAS loop shared by the update family: `transform` runs outside the
    /// lock and is retried until the swap applies against an unchanged value.
    private func mutate(_ transform: (Element) -> Element) -> (previous: Element, next: Element) {
        while true {
            let (current, isClosed) = storage.withLock { ($0.value, $0.isClosed) }
            // A closed flow can never apply the swap, so do not retry.
            guard !isClosed else { return (current, current) }
            let next = transform(current)
            if compareAndSet(expected: current, newValue: next) {
                return (current, next)
            }
        }
    }
}
