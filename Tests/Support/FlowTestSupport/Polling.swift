/// Polls `condition` until it returns true, with no deadline.
///
/// For state that has no change notification to suspend on, such as an actor
/// property read through `await`. The loop measures no time, so a stalled
/// process cannot make it give up early. A condition that never becomes true
/// parks the test until the run is cancelled, so use it only for conditions the
/// test itself has set in motion. Cancellation ends the wait.
///
/// The first spins yield, so a condition about to converge costs nothing. After
/// that it backs off to 1ms sleeps, which release the pool thread: a hot yield
/// loop occupies a cooperative-pool thread for its whole wait.
package func pollUntil(_ condition: @Sendable () async -> Bool) async {
    var spins = 0
    while !(await condition()) {
        if Task.isCancelled { return }
        spins += 1
        if spins <= 50 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// Suspends until the surrounding task is cancelled.
///
/// A sleep this long never elapses; cancellation is what ends it. Use it as the
/// body of a producer that must stay open until the test cancels it.
package func parkUntilCancelled() async {
    try? await Task.sleep(for: .seconds(1 << 40))
}
