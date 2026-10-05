package import FlowTestClock

/// What `driveTimeout` observed about an operation racing a `TestClock` deadline.
package struct TimeoutRun {
    /// Whether the operation was still running with the clock one millisecond
    /// short of the deadline.
    package let wasRunningBeforeDeadline: Bool
    /// The error the operation threw once the clock reached the deadline, or
    /// `nil` if it returned normally.
    package let error: (any Error)?
}

/// Runs `operation`, which must register exactly one sleep on `clock` (its
/// timeout) and then block, and walks the clock up to `deadline` by hand.
///
/// Waits for the timer to be registered, advances to one millisecond short of
/// `deadline` and records whether the operation is still running, then advances
/// the last millisecond and returns how it ended. Nothing here depends on real
/// elapsed time: the deadline fires when, and only when, the clock says so.
package func driveTimeout(
    on clock: TestClock,
    deadline: Duration,
    _ operation: @escaping @Sendable () async throws -> Void
) async throws -> TimeoutRun {
    let finished = Signal()
    let task = Task {
        defer { finished.fire() }
        try await operation()
    }
    try await clock.waitForSleepers(1)
    await clock.advance(by: deadline - .milliseconds(1))
    let wasRunning = !finished.hasFired
    await clock.advance(by: .milliseconds(1))
    let result = await task.result
    if case .failure(let error) = result {
        return TimeoutRun(wasRunningBeforeDeadline: wasRunning, error: error)
    }
    return TimeoutRun(wasRunningBeforeDeadline: wasRunning, error: nil)
}
