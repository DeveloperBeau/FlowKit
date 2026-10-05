import Foundation
public import FlowCore

/// Records the last value that fully passed through a point in a pipeline.
///
/// Pair with ``tap(after:)`` and ``waitForValue(where:)`` to deterministically
/// wait for a `TestClock`-driven operator (sample, throttle, debounce) to have
/// processed an emission before advancing the clock. A fixed number of
/// `Task.yield()`s cannot guarantee the operator's collect task has drained a
/// burst.
///
/// ```swift
/// let probe = FlowProbe<Int>()
/// let flow = upstream.asFlow().tap(after: probe).sample(every: .seconds(1), clock: clock)
/// await upstream.emit(3)
/// try await probe.waitForValue { $0 == 3 } // sample has stored 3
/// await clock.advance(by: .seconds(1))
/// ```
public actor FlowProbe<Value: Sendable> {
    private struct Waiter {
        let id: UUID
        let predicate: @Sendable (Value) -> Bool
        let continuation: CheckedContinuation<Void, any Error>
    }

    public private(set) var last: Value?
    private var waiters: [Waiter] = []

    public init() {}

    public func record(_ value: Value) {
        last = value
        let satisfied = waiters.filter { $0.predicate(value) }
        waiters.removeAll { waiter in satisfied.contains { $0.id == waiter.id } }
        for waiter in satisfied { waiter.continuation.resume() }
    }

    /// Suspends until the probe's latest value satisfies `predicate`, then
    /// returns. Returns at once if the latest value already does.
    ///
    /// The push counterpart of polling ``last``: each recorded value resumes
    /// the waiters it satisfies directly, so the wait has no poll loop and no
    /// real-time bound.
    ///
    /// - Parameter predicate: Tested against the latest value now and against
    ///   every value recorded afterwards.
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    public func waitForValue(where predicate: @escaping @Sendable (Value) -> Bool) async throws {
        if let last, predicate(last) { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, predicate: predicate, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

extension Flow {
    /// Delivers each value downstream first, then records it on `probe`.
    /// Once the probe has seen a value, the downstream operator has fully
    /// processed it.
    public func tap(after probe: FlowProbe<Element>) -> Flow<Element> {
        Flow { downstream in
            await self.collect { value in
                await downstream.emit(value)
                await probe.record(value)
            }
        }
    }
}

extension ThrowingFlow {
    /// Delivers each value downstream first, then records it on `probe`.
    /// Once the probe has seen a value, the downstream operator has fully
    /// processed it.
    public func tap(after probe: FlowProbe<Element>) -> ThrowingFlow<Element> {
        ThrowingFlow { downstream in
            try await self.collect { value in
                try await downstream.emit(value)
                await probe.record(value)
            }
        }
    }
}
