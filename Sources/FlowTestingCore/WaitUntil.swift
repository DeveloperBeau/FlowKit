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
public func waitUntil(
    timeout: Duration = .seconds(30),
    _ condition: @Sendable () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var spins = 0
    while !(await condition()) {
        if ContinuousClock.now >= deadline { return }
        spins += 1
        if spins <= 50 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
