import FlowTestClock

extension TestClock {
    /// Waits for `count` sleepers in its own task and reports whether the wait returned. The
    /// bound is hops, not time, so a `waitForSleepers` that parks although the sleepers are
    /// registered fails the assertion by name instead of hanging the run.
    package func registersSleepers(_ count: Int) async -> Bool {
        let returned = Signal()
        let waiter = Task {
            try await waitForSleepers(count)
            returned.fire()
        }
        let didReturn = await returned.firesWithinHops()
        waiter.cancel()
        return didReturn
    }
}
