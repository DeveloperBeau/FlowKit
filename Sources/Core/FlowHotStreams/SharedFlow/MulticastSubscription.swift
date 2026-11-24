import Foundation
internal import FlowSharedModels

internal actor MulticastSubscription<Element: Sendable> {
    private struct Subscriber: Sendable {
        let continuation: AsyncStream<Element>.Continuation
    }

    /// The per-subscriber buffering policy. A slow subscriber's buffer is
    /// bounded by this, so a fast emitter conflates or drops for it rather than
    /// letting its buffer grow without bound.
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
    /// The attached subscribers and the closed flag. They sit behind a lock,
    /// not behind the actor, so that `deliverWithoutSuspending(_:)` can reach
    /// them from synchronous code. Only actor-isolated methods add or remove
    /// an entry.
    private struct State: Sendable {
        var subscribers: [UUID: Subscriber] = [:]
        /// Set by `finishAll()` and never cleared. A closed subscription
        /// holds no subscribers and delivers nothing.
        var isClosed = false
    }

    private let state = Mutex(State())

    private struct CountWaiter {
        let isSatisfied: @Sendable (Int) -> Bool
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Callers suspended until the subscriber count satisfies their predicate.
    private var countWaiters: [UUID: CountWaiter] = [:]

    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    var subscriberCount: Int { state.withLock { $0.subscribers.count } }

    /// Registers a subscriber and returns its stream. After `finishAll()` the
    /// stream is already finished and nothing is registered.
    func makeSubscription() -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        let isRegistered = state.withLock { state in
            guard !state.isClosed else { return false }
            state.subscribers[id] = Subscriber(continuation: continuation)
            return true
        }
        guard isRegistered else {
            continuation.finish()
            return (id, stream)
        }
        resumeSatisfiedWaiters()
        return (id, stream)
    }

    /// Sends `value` to every subscriber. Returns `false`, and sends nothing,
    /// after `finishAll()`.
    @discardableResult
    func deliver(_ value: Element) -> Bool {
        deliverWithoutSuspending(value)
    }

    /// Yields `value` to every attached subscriber from any thread, without a
    /// hop to this actor. The lock is held for the whole fan-out, so two
    /// concurrent callers reach every subscriber in the same order, and a
    /// value is either sent to all of them before `finishAll()` or to none.
    /// Returns `false`, and sends nothing, after `finishAll()`.
    @discardableResult
    nonisolated func deliverWithoutSuspending(_ value: Element) -> Bool {
        state.withLock { state in
            guard !state.isClosed else { return false }
            for subscriber in state.subscribers.values {
                subscriber.continuation.yield(value)
            }
            return true
        }
    }

    func deliver(_ value: Element, to id: UUID) {
        state.withLock { $0.subscribers[id] }?.continuation.yield(value)
    }

    func unsubscribe(id: UUID) {
        if let subscriber = state.withLock({ $0.subscribers.removeValue(forKey: id) }) {
            subscriber.continuation.finish()
            resumeSatisfiedWaiters()
        }
    }

    /// Finishes every subscriber and closes the subscription for good. Each
    /// stream still hands out the values it had buffered before it ends.
    func finishAll() {
        let removed = state.withLock { state in
            state.isClosed = true
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for subscriber in removed {
            subscriber.continuation.finish()
        }
        resumeSatisfiedWaiters()
    }

    /// Suspends until the subscriber count satisfies `isSatisfied`, driven by
    /// this actor's own subscribe and unsubscribe path. Returns at once when it
    /// already does; throws `CancellationError` if the caller is cancelled.
    func waitForSubscriberCount(_ isSatisfied: @escaping @Sendable (Int) -> Bool) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if isSatisfied(subscriberCount) {
                    continuation.resume()
                } else {
                    countWaiters[id] = CountWaiter(isSatisfied: isSatisfied, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelCountWaiter(id) }
        }
    }

    private func cancelCountWaiter(_ id: UUID) {
        countWaiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    private func resumeSatisfiedWaiters() {
        let count = subscriberCount
        for (id, waiter) in countWaiters where waiter.isSatisfied(count) {
            countWaiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }
}
