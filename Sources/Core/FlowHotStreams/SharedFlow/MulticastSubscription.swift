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
    /// The attached subscribers. They sit behind a lock, not behind the actor,
    /// so that `deliverWithoutSuspending(_:)` can reach them from synchronous
    /// code. Only actor-isolated methods add or remove an entry.
    private let subscribers = Mutex<[UUID: Subscriber]>([:])

    private struct CountWaiter {
        let isSatisfied: @Sendable (Int) -> Bool
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Callers suspended until the subscriber count satisfies their predicate.
    private var countWaiters: [UUID: CountWaiter] = [:]

    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    var subscriberCount: Int { subscribers.withLock { $0.count } }

    func makeSubscription() -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        subscribers.withLock { $0[id] = Subscriber(continuation: continuation) }
        resumeSatisfiedWaiters()
        return (id, stream)
    }

    func deliver(_ value: Element) {
        deliverWithoutSuspending(value)
    }

    /// Yields `value` to every attached subscriber from any thread, without a
    /// hop to this actor. The lock is held for the whole fan-out, so two
    /// concurrent callers reach every subscriber in the same order.
    nonisolated func deliverWithoutSuspending(_ value: Element) {
        subscribers.withLock { subscribers in
            for subscriber in subscribers.values {
                subscriber.continuation.yield(value)
            }
        }
    }

    func deliver(_ value: Element, to id: UUID) {
        subscribers.withLock { $0[id] }?.continuation.yield(value)
    }

    func unsubscribe(id: UUID) {
        if let subscriber = subscribers.withLock({ $0.removeValue(forKey: id) }) {
            subscriber.continuation.finish()
            resumeSatisfiedWaiters()
        }
    }

    func finishAll() {
        let removed = subscribers.withLock { subscribers in
            defer { subscribers.removeAll() }
            return Array(subscribers.values)
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
