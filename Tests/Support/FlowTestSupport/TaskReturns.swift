extension Task {
    /// Whether the task returns, for a bounded join on a task under test.
    ///
    /// A watcher task awaits the task's result and fires a signal, and the
    /// check parks on that signal under a wall-clock safety net. The safety net
    /// never joins the task itself, so it returns even when the task ignores
    /// cancellation and never returns. In that case the task is cancelled and
    /// the check returns `false`. The watcher then stays parked until the task
    /// ends, which a test that has already failed can afford.
    ///
    /// Once this returns `true`, `value` and `result` return at once.
    package func returns(safetyNet: Duration = .seconds(30)) async -> Bool {
        let returned = Signal()
        Task<Void, Never> {
            _ = await self.result
            returned.fire()
        }
        guard await returned.fires(safetyNet: safetyNet) else {
            cancel()
            return false
        }
        return true
    }
}

extension Recorder {
    /// Whether at least `minimum` elements are recorded, for a bounded wait.
    ///
    /// The check parks on `wait(atLeast:)` in its own task, so an append alone
    /// makes it pass, however late the scheduler runs the recording task. The
    /// wall-clock bound is only a safety net that turns a missing append into a
    /// named assertion failure instead of a hung run.
    package func records(atLeast minimum: Int, safetyNet: Duration = .seconds(30)) async -> Bool {
        let reached = Signal()
        let waiter = Task {
            await wait(atLeast: minimum)
            reached.fire()
        }
        let didReach = await reached.fires(safetyNet: safetyNet)
        waiter.cancel()
        return didReach
    }
}
