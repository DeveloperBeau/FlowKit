/// Polls `condition` until it returns true.
///
/// The first spins yield, so a condition that is about to converge does so
/// with no added latency. After that the wait backs off to 1ms sleeps, which
/// release the pool thread entirely: a hot `while !cond { await Task.yield() }`
/// loop occupies a cooperative-pool thread for its whole wait, and a few of
/// those running concurrently starve the two-to-three-thread pools on CI
/// simulators until unrelated tests blow their timeouts.
///
/// Bounded by `timeout` so a condition that never converges returns control
/// to the caller, whose assertion then fails the test instead of hanging the
/// suite.
///
/// The timeout counts time the wait was running, not time the process was
/// stalled. If one pass of the loop takes longer than a second to come back
/// (a descheduled simulator, a blocked main thread), the stall is added to the
/// deadline: otherwise the first check after a long stall finds the deadline
/// passed before the work queued behind it has had a single turn.
@available(*, deprecated, message: "Read the flow with probing(_:) and suspend on its emissions, or use TestClock.waitForSleepers(_:) and FlowProbe.waitForValue(where:). For a deadline, pass a TestClock through waitUntil(timeout:clock:_:).")
public func waitUntil(
    timeout: Duration = .seconds(30),
    _ condition: @Sendable () async -> Bool
) async {
    await waitUntil(scaledTimeout(timeout), clock: ContinuousClock(), compensatingStalls: true, condition)
}

/// Polls `condition` until it returns true or `clock` has advanced by
/// `timeout`.
///
/// The deadline is measured on `clock`, so a `TestClock` expires it only when
/// the test advances the clock past `timeout`. The condition is still polled
/// on a real cadence (yields, then 1ms sleeps), but real elapsed time never
/// decides the outcome. `timeout` is used as given, without
/// ``flowTestTimeoutScale``, and no stall allowance applies: a virtual clock
/// moves only when the test moves it.
public func waitUntil<C: Clock>(
    timeout: Duration = .seconds(30),
    clock: C,
    _ condition: @Sendable () async -> Bool
) async where C.Duration == Duration {
    await waitUntil(timeout, clock: clock, compensatingStalls: false, condition)
}

private func waitUntil<C: Clock>(
    _ timeout: Duration,
    clock: C,
    compensatingStalls: Bool,
    _ condition: @Sendable () async -> Bool
) async where C.Duration == Duration {
    var deadline = clock.now.advanced(by: timeout)
    var lastPass = clock.now
    var spins = 0
    while !(await condition()) {
        let now = clock.now
        if compensatingStalls, lastPass.duration(to: now) > .seconds(1) {
            deadline = deadline.advanced(by: lastPass.duration(to: now))
        }
        lastPass = now
        if now >= deadline { return }
        spins += 1
        if spins <= 50 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
