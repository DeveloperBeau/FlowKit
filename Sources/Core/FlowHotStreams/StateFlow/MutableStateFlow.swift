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

    /// Sets `newValue` as the current value. Equivalent to writing `value`;
    /// a no-op when `newValue` equals the current value.
    public func send(_ newValue: Element) {
        storage.withLock { state in
            guard newValue != state.value else { return }
            state.value = newValue
            state.seq += 1
            pipeline.yield(Stamped(seq: state.seq, value: newValue))
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
    /// whether the swap happened.
    @discardableResult
    public func compareAndSet(expected: Element, newValue: Element) -> Bool {
        storage.withLock { state in
            guard state.value == expected else { return false }
            guard newValue != state.value else { return true }
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
            let current = value
            let next = transform(current)
            if compareAndSet(expected: current, newValue: next) {
                return (current, next)
            }
        }
    }
}
