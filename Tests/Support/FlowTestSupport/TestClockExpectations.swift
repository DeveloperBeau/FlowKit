import FlowTestClock

extension TestClock {
    /// Waits for `count` sleepers in its own task and reports whether the wait returned. The
    /// check parks on the push wait, so the scheduler can start the sleeper tasks as late as
    /// it likes. A wall-clock safety net turns a `waitForSleepers` that never returns into a
    /// named assertion failure instead of a hung run.
    package func registersSleepers(_ count: Int) async -> Bool {
        let returned = Signal()
        let waiter = Task {
            try await waitForSleepers(count)
            returned.fire()
        }
        let didReturn = await returned.fires()
        waiter.cancel()
        return didReturn
    }

    /// Waits for the clock to have no sleepers in its own task and reports whether the wait
    /// returned. Same shape and safety net as `registersSleepers(_:)`.
    package func registersNoSleepers() async -> Bool {
        let returned = Signal()
        let waiter = Task {
            try await waitForNoSleepers()
            returned.fire()
        }
        let didReturn = await returned.fires()
        waiter.cancel()
        return didReturn
    }
}
