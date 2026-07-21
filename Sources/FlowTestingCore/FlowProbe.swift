public import FlowCore

/// Records the last value that fully passed through a point in a pipeline.
///
/// Pair with ``tap(after:)`` and `waitUntil` to deterministically wait for a
/// `TestClock`-driven operator (sample, throttle, debounce) to have processed
/// an emission before advancing the clock — a fixed number of `Task.yield()`s
/// cannot guarantee the operator's collect task has drained a burst.
///
/// ```swift
/// let probe = FlowProbe<Int>()
/// let flow = upstream.asFlow().tap(after: probe).sample(every: .seconds(1), clock: clock)
/// await upstream.emit(3)
/// await waitUntil { await probe.last == 3 } // sample has stored 3
/// await clock.advance(by: .seconds(1))
/// ```
public actor FlowProbe<Value: Sendable> {
    public private(set) var last: Value?

    public init() {}

    public func record(_ value: Value) { last = value }
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
