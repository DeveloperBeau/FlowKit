import Foundation
import FlowSharedModels

/// A thread-safe log a test appends to from a callback or collector, and waits
/// on for a condition over everything recorded so far.
///
/// The deadline-free alternative to polling a lock-guarded array: `wait(until:)`
/// suspends until an append makes `condition` true, however long that takes.
/// Cancelling a waiter ends its wait.
package final class Recorder<Element: Sendable>: Sendable {
    private struct Waiter {
        let condition: @Sendable ([Element]) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var elements: [Element] = []
        var waiters: [UUID: Waiter] = [:]
    }

    private let state = Mutex(State())

    package init() {}

    /// Everything recorded so far, oldest first.
    package var elements: [Element] { state.withLock { $0.elements } }

    package var count: Int { state.withLock { $0.elements.count } }

    package var last: Element? { state.withLock { $0.elements.last } }

    package func record(_ element: Element) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.elements.append(element)
            let satisfied = state.waiters.filter { $0.value.condition(state.elements) }
            for id in satisfied.keys { state.waiters.removeValue(forKey: id) }
            return satisfied.values.map(\.continuation)
        }
        for continuation in ready { continuation.resume() }
    }

    /// Suspends until `condition` holds for the recorded elements.
    package func wait(until condition: @escaping @Sendable ([Element]) -> Bool) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let shouldResumeNow = state.withLock { state -> Bool in
                    if condition(state.elements) || Task.isCancelled { return true }
                    state.waiters[id] = Waiter(condition: condition, continuation: continuation)
                    return false
                }
                if shouldResumeNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.continuation.resume()
        }
    }

    /// Suspends until at least `minimum` elements are recorded.
    package func wait(atLeast minimum: Int) async {
        await wait { $0.count >= minimum }
    }
}
