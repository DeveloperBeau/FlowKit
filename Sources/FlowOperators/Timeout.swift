public import FlowCore
import FlowSharedModels

/// Thrown by `timeout(for:clock:)` when the gap between emissions — or
/// before the first emission — exceeds the allowed duration.
public struct FlowTimeoutError: Error, Equatable, Sendable {
    public init() {}
}

extension ThrowingFlow {
    /// Fails with ``FlowTimeoutError`` if more than `duration` passes between
    /// emissions, including before the first. Values emitted in time flow
    /// through unchanged; an upstream error propagates as-is.
    public func timeout(
        for duration: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> ThrowingFlow<Element> {
        let upstream = self
        return ThrowingFlow { downstream in
            try await withThrowingTaskGroup(of: Void.self) { group in
                let lastActivity = Mutex(clock.now)
                let finished = Mutex(false)

                group.addTask {
                    try await upstream.collect { value in
                        try await downstream.emit(value)
                        lastActivity.withLock { $0 = clock.now }
                    }
                    finished.withLock { $0 = true }
                }
                // Watchdog: sleeps until the current deadline; a value arriving
                // in the meantime pushes the deadline and the loop re-sleeps.
                group.addTask {
                    while true {
                        let deadline = lastActivity.withLock { $0 }.advanced(by: duration)
                        try await clock.sleep(until: deadline, tolerance: nil)
                        if finished.withLock({ $0 }) { return }
                        if lastActivity.withLock({ $0 }).advanced(by: duration) <= clock.now {
                            throw FlowTimeoutError()
                        }
                    }
                }

                // First child to finish wins: normal completion, upstream
                // error, or the watchdog's timeout.
                try await group.next()
                group.cancelAll()
            }
        }
    }
}

extension Flow {
    /// Fails with ``FlowTimeoutError`` if more than `duration` passes between
    /// emissions, including before the first. The result is a `ThrowingFlow`
    /// because timing out is a failure.
    public func timeout(
        for duration: Duration,
        clock: some Clock<Duration> = ContinuousClock()
    ) -> ThrowingFlow<Element> {
        mapThrowing { $0 }.timeout(for: duration, clock: clock)
    }
}
