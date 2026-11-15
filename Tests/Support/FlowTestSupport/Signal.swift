import Foundation
import FlowSharedModels
import FlowTesting

/// A one-shot event a test fires and any number of tasks wait on.
///
/// The deadline-free way to order two tasks: the waiter suspends until `fire()`
/// resumes it, however long that takes. Waiting after the event has fired
/// returns at once, and cancelling a waiter ends its wait.
package final class Signal: Sendable {
    private struct State {
        var isFired = false
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    package init() {}

    /// Whether `fire()` has been called.
    package var hasFired: Bool { state.withLock { $0.isFired } }

    package func fire() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isFired = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    package func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let shouldResumeNow = state.withLock { state -> Bool in
                    if state.isFired || Task.isCancelled { return true }
                    state.waiters[id] = continuation
                    return false
                }
                if shouldResumeNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.resume()
        }
    }
}

extension Signal {
    /// Whether the signal fires, for asserting that a waiter under test resumed.
    ///
    /// The check parks on `wait()`, so `fire()` alone makes it pass, however
    /// late the scheduler runs the firing task. The wall-clock bound is only a
    /// safety net. A correct waiter never reaches it, and a broken waiter fails
    /// the assertion by name instead of parking the run.
    package func fires(safetyNet: Duration = .seconds(30)) async -> Bool {
        (try? await withThrowingTimeout(safetyNet) {
            await self.wait()
            return true
        }) ?? false
    }

    /// Whether the signal is fired within a bounded number of scheduler hops.
    ///
    /// Use this only for negative checks, to assert that a waiter did not
    /// resume. A hop count does not make sure that the scheduler runs a
    /// ready task, so a positive check uses `fires()` instead.
    package func firesWithinHops(_ hops: Int = 1000) async -> Bool {
        for _ in 0..<hops {
            if hasFired { return true }
            await Task.yield()
        }
        return hasFired
    }
}
