import Foundation
import FlowSharedModels

internal actor MulticastSubscription<Element: Sendable> {
    private struct Subscriber {
        let continuation: AsyncStream<Element>.Continuation
    }

    /// The per-subscriber buffering policy. A slow subscriber's buffer is
    /// bounded by this, so a fast emitter conflates or drops for it rather than
    /// letting its buffer grow without bound.
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
    private var subscribers: [UUID: Subscriber] = [:]

    private struct Registration: Sendable {
        let continuation: AsyncStream<Element>.Continuation
        /// Whether the owner still has to yield its replay to this subscriber.
        /// `deliver` skips the subscriber until then, so the replay comes first.
        var awaitsReplay: Bool
    }

    /// Subscribers added by `register`. They sit behind a lock, not in actor
    /// state, so that synchronous code can add and remove them.
    private let registrations = Mutex<[UUID: Registration]>([:])

    private struct CountWaiter {
        let isSatisfied: @Sendable (Int) -> Bool
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Callers suspended until the subscriber count satisfies their predicate.
    private var countWaiters: [UUID: CountWaiter] = [:]

    init(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) {
        self.bufferingPolicy = bufferingPolicy
    }

    var subscriberCount: Int {
        subscribers.count + registrations.withLock { $0.count }
    }

    func makeSubscription() -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        subscribers[id] = Subscriber(continuation: continuation)
        resumeSatisfiedWaiters()
        return (id, stream)
    }

    /// Adds a subscriber without a suspension. Every `deliver` that starts
    /// after this returns reaches it, except while it waits for its replay.
    nonisolated func register(awaitingReplay: Bool) -> (UUID, AsyncStream<Element>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        registrations.withLock {
            $0[id] = Registration(continuation: continuation, awaitsReplay: awaitingReplay)
        }
        notifyCountWaiters()
        return (id, stream)
    }

    /// Removes a subscriber that `register` added and finishes its stream.
    /// Does nothing when it is already removed.
    nonisolated func unregister(id: UUID) {
        guard let registration = registrations.withLock({ $0.removeValue(forKey: id) }) else { return }
        registration.continuation.finish()
        notifyCountWaiters()
    }

    /// Yields `elements()` to each registered subscriber that still waits for
    /// its replay, and lets `deliver` reach it from then on. `elements` is not
    /// called when no subscriber waits.
    nonisolated func replayToRegistrations(_ elements: () -> [Element]) {
        registrations.withLock { registrations in
            guard registrations.values.contains(where: \.awaitsReplay) else { return }
            let replay = elements()
            registrations = registrations.mapValues { registration in
                guard registration.awaitsReplay else { return registration }
                for value in replay {
                    registration.continuation.yield(value)
                }
                return Registration(continuation: registration.continuation, awaitsReplay: false)
            }
        }
    }

    /// The count waiters are actor state, and a registration changes the count
    /// from synchronous code, so the check hops onto the actor.
    private nonisolated func notifyCountWaiters() {
        Task { await self.resumeSatisfiedWaiters() }
    }

    func deliver(_ value: Element) {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(value)
        }
        // The yield stays under the lock, so it cannot interleave with a
        // replay that another thread yields to the same subscriber.
        registrations.withLock { registrations in
            for registration in registrations.values where !registration.awaitsReplay {
                registration.continuation.yield(value)
            }
        }
    }

    func deliver(_ value: Element, to id: UUID) {
        subscribers[id]?.continuation.yield(value)
    }

    func unsubscribe(id: UUID) {
        if let subscriber = subscribers.removeValue(forKey: id) {
            subscriber.continuation.finish()
            resumeSatisfiedWaiters()
        }
    }

    func finishAll() {
        for subscriber in subscribers.values {
            subscriber.continuation.finish()
        }
        subscribers.removeAll()
        let registered = registrations.withLock { registrations in
            defer { registrations.removeAll() }
            return Array(registrations.values)
        }
        for registration in registered {
            registration.continuation.finish()
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
