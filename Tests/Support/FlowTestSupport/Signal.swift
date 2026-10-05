import Foundation
import FlowSharedModels

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
